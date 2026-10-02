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
    public private(set) var hasAskedNotificationQuestion = false

    private let catalog: StationCatalog
    let liveActivity: StationLiveActivityModel
    let inputs: Inputs
    private let services: Services
    let configuration: Configuration
    private var state: AutoLiveActivityState {
        didSet { stateDidChange(from: oldValue) }
    }
    private var appPhase = AppPhase.background
    var appIsActive: Bool { appPhase == .active }
    private var hasAskedForNotifications = false
    private var pendingTappedStationId: String?
    private var plannedRegions: RegionPlanKey?
    private var hasClearedRegions = false
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored var feedTask: Task<Void, Never>?

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

    public func setAppPhase(_ phase: AppPhase) {
        let wasActive = appIsActive
        appPhase = phase
        feedAfterActivityChange(wasActive: wasActive)
        if phase == .background, state.pendingArrivalStationId != nil {
            Task { await evaluate(position: nil) }
        }
    }

    public func appDidBecomeActive() async {
        guard appIsActive else { return }
        syncWithSystem()
        if liveActivity.isShowing {
            services.locationKeeper.begin()
        }
        askForNotificationsIfAllowed()
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

    public func notificationActionChosen(_ action: ArrivalNotificationAction) async {
        await snooze(for: action.snoozeDuration)
    }

    public func handleRegionEvent(enteredRegionId: String?, lastKnownFix: PositionFix?) async {
        guard inputs.locationService.source == .realGPS else { return }
        let fix = WatchedRegion.fix(
            afterEnteringRegionId: enteredRegionId,
            lastKnownFix: lastKnownFix,
            now: configuration.now(),
            catalog: catalog
        )
        guard let fix else { return }
        await handle(fix, maximumAge: AutoLiveActivityRules.maximumMonitoredPositionAge)
    }

    public func startByHand(_ station: Station) async {
        let isNear = precisePosition().map {
            $0.distance(to: station.coordinate) <= AutoLiveActivityRules.stopRadiusMeters
        }
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
            _ = inputs.locationService.fix
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.positionDidChange()
            }
        }
    }

    private func positionDidChange() {
        observePosition()
        guard let fix = inputs.locationService.fix else { return }
        Task { await handle(fix) }
    }

    private func followPositionIfShowing() {
        guard state.shown != nil else { return }
        services.locationKeeper.begin()
        startFeedAfterLaunch()
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

    private func evaluate(position: Coordinate?) async {
        syncWithSystem()
        let response = AutoLiveActivityRules.ArrivalResponse(
            appPhase: appPhase,
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

    func syncWithSystem() {
        liveActivity.syncWithSystem()
        guard !liveActivity.isShowing, state.shown != nil else { return }
        state.shown = nil
        services.locationKeeper.end()
        restartFeed(fetchNow: false)
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
}

private extension AutoLiveActivityModel {
    func scheduleTimer() {
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

    func precisePosition() -> Coordinate? {
        guard let fix = inputs.locationService.fix else { return nil }
        guard inputs.locationService.source != .realGPS || AutoLiveActivityRules.isPrecise(fix) else {
            return nil
        }
        return fix.coordinate
    }

    func trusts(_ fix: PositionFix, maximumAge: TimeInterval = AutoLiveActivityRules.maximumPositionAge) -> Bool {
        guard inputs.locationService.source == .realGPS else { return true }
        return AutoLiveActivityRules.trusts(fix, now: configuration.now(), maximumAge: maximumAge)
    }

    func handle(_ fix: PositionFix, maximumAge: TimeInterval = AutoLiveActivityRules.maximumPositionAge) async {
        guard trusts(fix, maximumAge: maximumAge) else {
            await refreshRegions(around: fix.coordinate)
            return
        }
        await handle(fix.coordinate)
    }

    func handle(_ position: Coordinate) async {
        await evaluate(position: position)
        await refreshRegions(around: position)
    }

    func askForNotificationsIfAllowed() {
        guard !hasAskedForNotifications, inputs.permission.authorization == .authorized else { return }
        hasAskedForNotifications = true
        Task { [weak self, permission = inputs.permission, notifier = services.notifier] in
            await permission.waitForAlwaysQuestion()
            await notifier.requestAuthorization()
            self?.hasAskedNotificationQuestion = true
        }
    }

    func trains(for station: Station) -> NextTrainsState {
        if inputs.screenTrains.updatingStationId == station.id {
            return inputs.screenTrains.state(for: station)
        }
        return inputs.liveActivityTrains.state(for: station)
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
