import Foundation
import Observation

@MainActor
@Observable
public final class AutoLiveActivityModel {
    private struct RegionPlanKey {
        let center: Coordinate
        let stopStationId: String?
    }

    public private(set) var shownStation: Station?

    private let catalog: StationCatalog
    private let liveActivity: StationLiveActivityModel
    private let inputs: Inputs
    private let services: Services
    private let configuration: Configuration
    private var state: AutoLiveActivityState {
        didSet { stateDidChange(from: oldValue) }
    }
    private var appIsActive = false
    private var hasAskedForNotifications = false
    private var pendingTappedStationId: String?
    private var plannedRegions: RegionPlanKey?
    private var hasClearedRegions = false
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var feedTask: Task<Void, Never>?

    public init(
        catalog: StationCatalog,
        liveActivity: StationLiveActivityModel,
        inputs: Inputs,
        services: Services,
        configuration: Configuration
    ) {
        self.catalog = catalog
        self.liveActivity = liveActivity
        self.inputs = inputs
        self.services = services
        self.configuration = configuration
        var state = configuration.store.load()
        if !liveActivity.isShowing {
            state.shown = nil
        }
        self.state = state
        stateDidChange(from: AutoLiveActivityState())
        observePosition()
        observeScreenStation()
        observeAutomaticMode()
        followPositionIfShowing()
    }

    deinit {
        timerTask?.cancel()
        feedTask?.cancel()
    }

    public func setAppActive(_ isActive: Bool) async {
        appIsActive = isActive
        guard isActive else {
            restartFeed(fetchNow: false)
            return
        }
        syncWithSystem()
        if liveActivity.isShowing {
            services.locationKeeper.begin()
        }
        await askForNotificationsIfAllowed()
        await openTappedStation()
        await evaluate(position: nil)
        plannedRegions = nil
        await refreshRegions(around: inputs.locationService.position)
        restartFeed(fetchNow: false)
    }

    public func notificationTapped(stationId: String) async {
        pendingTappedStationId = stationId
        await openTappedStation()
    }

    public func handleMonitoredPosition(_ position: Coordinate) async {
        guard inputs.locationService.source == .realGPS else { return }
        await handle(position)
    }

    public func startByHand(_ station: Station) async {
        let position = inputs.locationService.position
        let isNear = position.map { $0.distance(to: station.coordinate) <= AutoLiveActivityRules.stopRadiusMeters }
        state.shown = .init(stationId: station.id, startedAt: configuration.now(), hasBeenNear: isNear ?? false)
        await show(station)
        await refreshRegions(around: inputs.locationService.position)
    }

    public func stopByHand() async {
        state.shown = nil
        await endLiveActivity()
        await refreshRegions(around: inputs.locationService.position)
    }

    public func snooze(for duration: SnoozeDuration) async {
        inputs.automaticMode.snooze(for: duration)
        await stopByHand()
    }

    public func screenTrainsChanged(for station: Station) async {
        guard shownStation?.id == station.id else { return }
        await liveActivity.update(station: station, trains: inputs.screenTrains.state(for: station))
    }

    private func observePosition() {
        withObservationTracking {
            _ = inputs.locationService.position
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.positionDidChange()
            }
        }
    }

    private func positionDidChange() {
        observePosition()
        guard let position = inputs.locationService.position else { return }
        Task { await handle(position) }
    }

    private func followPositionIfShowing() {
        guard state.shown != nil else { return }
        services.locationKeeper.begin()
        restartFeed(fetchNow: true)
        guard inputs.permission.authorization == .authorized else { return }
        inputs.locationService.start()
    }

    private func observeScreenStation() {
        withObservationTracking {
            _ = inputs.screenTrains.updatingStationId
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeScreenStation()
                self?.restartFeed(fetchNow: false)
            }
        }
    }

    private func observeAutomaticMode() {
        withObservationTracking {
            _ = inputs.automaticMode.mode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeAutomaticMode()
                if !self.inputs.automaticMode.allowsAutomaticStart {
                    self.services.notifier.withdraw()
                }
            }
        }
    }

    private func handle(_ position: Coordinate) async {
        await evaluate(position: position)
        await refreshRegions(around: position)
    }

    private func evaluate(position: Coordinate?) async {
        syncWithSystem()
        let response = AutoLiveActivityRules.ArrivalResponse(
            appIsActive: appIsActive,
            allowsAutomaticStart: inputs.automaticMode.allowsAutomaticStart
        )
        let decision = configuration.rules.decide(
            state: state,
            position: position,
            now: configuration.now(),
            onArrival: response,
            catalog: catalog
        )
        state = decision.state
        for action in decision.actions {
            await perform(action)
        }
    }

    private func perform(_ action: AutoLiveActivityRules.Action) async {
        switch action {
        case .notify(let station):
            await services.notifier.notify(station)
        case .start(let station):
            await show(station)
        case .switchTo(let station):
            await liveActivity.update(station: station, trains: trains(for: station))
            restartFeed(fetchNow: true)
        case .end:
            await endLiveActivity()
        case .withdrawNotification:
            services.notifier.withdraw()
        }
    }

    private func show(_ station: Station) async {
        await liveActivity.start(station: station, trains: trains(for: station))
        guard liveActivity.isShowing else {
            state.shown = nil
            return
        }
        services.locationKeeper.begin()
        restartFeed(fetchNow: true)
    }

    private func endLiveActivity() async {
        await liveActivity.stop()
        services.locationKeeper.end()
        restartFeed(fetchNow: false)
    }

    private func syncWithSystem() {
        liveActivity.syncWithSystem()
        guard !liveActivity.isShowing, state.shown != nil else { return }
        state.shown = nil
        services.locationKeeper.end()
        restartFeed(fetchNow: false)
    }

    private func askForNotificationsIfAllowed() async {
        guard !hasAskedForNotifications, inputs.permission.authorization == .authorized else { return }
        hasAskedForNotifications = true
        await services.notifier.requestAuthorization()
    }

    private func openTappedStation() async {
        guard appIsActive, let stationId = pendingTappedStationId else { return }
        pendingTappedStationId = nil
        guard let station = catalog.station(withId: stationId) else { return }
        state.arrivalStationId = stationId
        if liveActivity.isShowing, let shown = state.shown {
            guard shown.stationId != stationId else { return }
            state.shown = .init(stationId: stationId, startedAt: shown.startedAt, hasBeenNear: true)
            await perform(.switchTo(station))
        } else {
            state.shown = .init(stationId: stationId, startedAt: configuration.now(), hasBeenNear: true)
            await show(station)
        }
    }

    private func trains(for station: Station) -> NextTrainsState {
        if inputs.screenTrains.updatingStationId == station.id {
            return inputs.screenTrains.state(for: station)
        }
        return inputs.liveActivityTrains.state(for: station)
    }

    private func stateDidChange(from oldValue: AutoLiveActivityState) {
        guard state != oldValue else { return }
        let station = state.shown.flatMap { catalog.station(withId: $0.stationId) }
        if station != shownStation {
            shownStation = station
        }
        configuration.store.save(state)
        if oldValue.shown?.startedAt != state.shown?.startedAt {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        timerTask = nil
        guard let shown = state.shown else { return }
        let deadline = shown.startedAt.addingTimeInterval(configuration.rules.maximumDuration)
        let remaining = max(0, deadline.timeIntervalSince(configuration.now()))
        timerTask = Task { [weak self, sleep = configuration.sleep] in
            do {
                try await sleep(.seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            Task { @MainActor in
                await self?.evaluate(position: nil)
                guard let self, self.state.shown?.startedAt == shown.startedAt else { return }
                self.scheduleTimer()
            }
        }
    }
}

private extension AutoLiveActivityModel {
    func restartFeed(fetchNow: Bool) {
        feedTask?.cancel()
        feedTask = nil
        guard let station = shownStation, liveActivity.isShowing else { return }
        if appIsActive {
            guard inputs.screenTrains.updatingStationId != station.id else { return }
            feedTask = Task { [weak self] in
                await self?.keepFeeding(station)
            }
        } else {
            feedTask = Task { [weak self] in
                await self?.keepFeedingInBackground(station, fetchNow: fetchNow)
            }
        }
    }

    func keepFeedingInBackground(_ station: Station, fetchNow: Bool) async {
        var asksPRIM = true
        var waits = !fetchNow
        while !Task.isCancelled {
            if waits {
                let staleDate = liveActivity.content?.staleDate
                let delay = asksPRIM
                    ? BackgroundTrainsRefresh.delay(untilStale: staleDate, now: configuration.now())
                    : BackgroundTrainsRefresh.maximumDelay
                do {
                    try await configuration.sleep(.seconds(delay))
                } catch {
                    return
                }
            }
            waits = true
            syncWithSystem()
            guard liveActivity.isShowing else { return }
            guard asksPRIM else { continue }
            await feed(station)
            asksPRIM = BackgroundTrainsRefresh.shouldAskAgain(after: inputs.liveActivityTrains.state(for: station))
        }
    }

    func keepFeeding(_ station: Station) async {
        while !Task.isCancelled {
            await feed(station)
            do {
                try await configuration.sleep(NextTrainsModel.refreshInterval)
            } catch {
                return
            }
        }
    }

    func feed(_ station: Station) async {
        let trains = inputs.liveActivityTrains
        await trains.refresh(for: station)
        guard !Task.isCancelled, shownStation?.id == station.id else { return }
        await liveActivity.update(station: station, trains: trains.state(for: station))
    }

    func refreshRegions(around position: Coordinate?) async {
        guard inputs.locationService.source == .realGPS else {
            guard plannedRegions != nil || !hasClearedRegions else { return }
            plannedRegions = nil
            hasClearedRegions = true
            await services.regionWatcher.watch([])
            return
        }
        guard let position else { return }
        hasClearedRegions = false
        let stopStationId = state.shown?.stationId ?? state.arrivalStationId
        if let plannedRegions, plannedRegions.stopStationId == stopStationId,
           plannedRegions.center.distance(to: position) < StationRegionPlan.replanDistanceMeters {
            return
        }
        plannedRegions = RegionPlanKey(center: position, stopStationId: stopStationId)
        let regions = StationRegionPlan.regions(
            around: position,
            stopStation: stopStationId.flatMap(catalog.station(withId:)),
            catalog: catalog
        )
        await services.regionWatcher.watch(regions)
    }
}
