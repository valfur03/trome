import Foundation
import Observation

@MainActor
@Observable
public final class AutoLiveActivityModel {
    struct RegionPlanKey {
        let center: Coordinate
        let stopStationId: String?
    }

    public private(set) var shownStation: Station?
    public private(set) var pausedStation: PausedStation?
    public internal(set) var cannotFindPosition = false
    public private(set) var hasAskedNotificationQuestion = false

    let catalog: StationCatalog
    let liveActivity: StationLiveActivityModel
    let inputs: Inputs
    let services: Services
    let configuration: Configuration
    var state: AutoLiveActivityState {
        didSet { stateDidChange(from: oldValue) }
    }
    private(set) var appPhase = AppPhase.background
    var appIsActive: Bool { appPhase == .active }
    private(set) var hasAskedForNotifications = false
    var plannedRegions: RegionPlanKey?
    var hasClearedRegions = false
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored var feedTask: Task<Void, Never>?
    @ObservationIgnored var pauseTimerTask: Task<Void, Never>?
    @ObservationIgnored var removedOutsideTheApp: AutoLiveActivityState.Shown?
    @ObservationIgnored var lastLoggedOutcomeKey: String?
    @ObservationIgnored var secondChances: [String: ArrivalSecondChance] = [:]
    @ObservationIgnored var secondChanceTask: Task<Void, Never>?
    /// Whether the keeper runs: the Wake log says it when the app may be suspended.
    @ObservationIgnored var isKeepingAwake = false

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
        let goneSinceTheLastRun = liveActivity.isShowing ? nil : state.shown
        if !liveActivity.isShowing {
            state = configuration.rules.liveActivityIsGone(
                from: state,
                activitiesAreEnabled: liveActivity.areActivitiesEnabled
            )
            state.exampleStartedAt = nil
        }
        self.state = state
        stateDidChange(from: AutoLiveActivityState())
        if let goneSinceTheLastRun {
            logEndOutsideTheApp(of: goneSinceTheLastRun)
        }
        if liveActivity.isShowing {
            adoptThePushedLiveActivity()
        }
        endPauseIfOver()
        watchLiveActivityChanges()
        services.locationKeeper.onPosition = { [weak self] fix in
            self?.inputs.locationService.takeBackgroundFix(fix)
        }
        observePosition()
        observeScreenStation()
        observeAutomaticMode()
        followPositionIfShowing()
        if showsExample {
            restartFeed(fetchNow: false)
        }
    }

    deinit {
        timerTask?.cancel()
        feedTask?.cancel()
        pauseTimerTask?.cancel()
        secondChanceTask?.cancel()
    }

    public func setAppPhase(_ phase: AppPhase) {
        let wasActive = appIsActive
        logScreenChange(from: appPhase, to: phase)
        appPhase = phase
        if phase != .active {
            cannotFindPosition = false
        }
        inputs.locationService.setOnScreen(phase != .background)
        feedAfterActivityChange(wasActive: wasActive)
        if phase == .background, state.pendingArrivalStationId != nil {
            Task { await evaluate(position: nil) }
        }
    }

    public func appDidBecomeActive() async {
        guard appIsActive else { return }
        inputs.screenTrains.askAgainAfterARefusal()
        inputs.liveActivityTrains.askAgainAfterARefusal()
        syncWithSystem()
        if liveActivity.isShowing, !showsExample {
            followPositionInBackground()
        }
        askForNotificationsIfAllowed()
        await evaluate(position: nil)
        await restartTheExampleAtTheFront()
        plannedRegions = nil
        await refreshRegions(around: inputs.locationService.position)
        restartFeed(fetchNow: false)
        await resumeOpenArrival()
    }

    public func startByHand(_ station: Station) async {
        endPause(at: station.id, reason: "start by hand")
        let isNear = precisePosition().map {
            $0.distance(to: station.coordinate) <= AutoLiveActivityRules.stopRadiusMeters
        }
        state.shown = .init(stationId: station.id, startedAt: configuration.now(), hasBeenNear: isNear ?? false)
        await show(station)
        if liveActivity.isShowing {
            logStartByHand(at: station)
        }
        await refreshRegions(around: inputs.locationService.position)
    }

    public func stopByHand() async {
        await stop(because: .stoppedByHand)
    }

    public func snooze(for duration: SnoozeDuration) async {
        state.openArrivalStationId = nil
        inputs.automaticMode.snooze(for: duration)
        await stop(because: .snoozed(duration))
    }

    private func stop(because ending: LiveActivityEnding) async {
        if state.shown != nil {
            log(ending)
        }
        state.shown = nil
        await endLiveActivity()
        await refreshRegions(around: inputs.locationService.position)
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
        let origin = inputs.locationService.fixOrigin
        Task { await handle(fix, from: origin) }
    }

    private func followPositionIfShowing() {
        guard state.shown != nil else { return }
        followPositionInBackground()
        startFeedAfterLaunch()
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
                    self.endSecondChancesIfAutomaticStartIsOff()
                }
                if self.inputs.automaticMode.mode == .turnedOff {
                    await self.automaticModeTurnedOff()
                }
            }
        }
    }

    func perform(_ action: AutoLiveActivityRules.Action) async {
        switch action {
        case .startInTheBackground(let station):
            await startInTheBackground(at: station)
        case .start(let station):
            await show(station)
        case .switchTo(let station):
            await liveActivity.update(station: station, trains: trains(for: station))
            restartFeed(fetchNow: true)
        case .end:
            await endLiveActivity()
        }
    }

    private func show(_ station: Station) async {
        if !liveActivity.isShowing {
            inputs.liveActivityTrains.askAgainAfterARefusal()
        }
        await liveActivity.start(station: station, trains: trains(for: station))
        guard liveActivity.isShowing else {
            forgetShownLiveActivity()
            return
        }
        removedOutsideTheApp = nil
        followPositionInBackground()
        restartFeed(fetchNow: true)
    }

    private func endLiveActivity() async {
        await liveActivity.stop()
        guard !liveActivity.isShowing else { return }
        stopFollowingPositionInBackground()
        restartFeed(fetchNow: false)
    }

    func syncWithSystem() {
        liveActivity.syncWithSystem()
        forgetTheExampleIfRemoved()
        if liveActivity.isShowing, adoptThePushedLiveActivity() {
            removedOutsideTheApp = nil
            followPositionInBackground()
            restartFeed(fetchNow: false)
        }
        guard !liveActivity.isShowing, let shown = state.shown else { return }
        removedOutsideTheApp = shown
        logEndOutsideTheApp(of: shown)
        forgetShownLiveActivity()
        stopFollowingPositionInBackground()
        restartFeed(fetchNow: false)
    }

}

private extension AutoLiveActivityModel {
    func stateDidChange(from oldValue: AutoLiveActivityState) {
        guard state != oldValue else { return }
        let station = state.shown.flatMap { catalog.station(withId: $0.stationId) }
        if station != shownStation {
            shownStation = station
        }
        configuration.store.save(state)
        if oldValue.shown?.startedAt != state.shown?.startedAt {
            scheduleTimer()
        }
        if oldValue.pause != state.pause {
            pausedStation = state.pause.flatMap { pause in
                catalog.station(withId: pause.stationId).map { PausedStation(station: $0, end: pause.end) }
            }
            schedulePauseEnd()
        }
    }

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

    func askForNotificationsIfAllowed() {
        guard !hasAskedForNotifications, inputs.permission.authorization == .authorized else { return }
        hasAskedForNotifications = true
        Task { [weak self, permission = inputs.permission, notifications = services.notifications] in
            await permission.waitForAlwaysQuestion()
            guard let self else { return }
            // The location questions also end when the rider leaves the app (after Allow Once, iOS shows no
            // Always question): the question then waits for the next return, so that iOS never shows it out of the app.
            guard self.appIsActive else {
                self.hasAskedForNotifications = false
                return
            }
            await notifications.requestAuthorization()
            self.hasAskedNotificationQuestion = true
        }
    }
}

extension AutoLiveActivityModel {
    func evaluate(
        position: Coordinate?,
        asAResume: Bool = false,
        logsEveryOutcome: Bool = false,
        from origin: PositionOrigin? = nil
    ) async {
        syncWithSystem()
        endPauseIfOver()
        let decide = asAResume
            ? configuration.rules.resume(state:position:now:onArrival:catalog:)
            : configuration.rules.decide(state:position:now:onArrival:catalog:)
        let decision = decide(state, position, configuration.now(), arrivalResponse, catalog)
        await apply(decision, logsEveryOutcome: logsEveryOutcome, from: origin)
    }

    func apply(
        _ decision: AutoLiveActivityRules.Decision,
        logsEveryOutcome: Bool,
        from origin: PositionOrigin? = nil
    ) async {
        log(decision.ending, from: origin)
        log(decision.arrival, everyOutcome: logsEveryOutcome, from: origin)
        state = decision.state
        for action in decision.actions {
            await perform(action)
        }
        endSecondChances(on: decision.arrival)
    }

    func handle(
        _ position: Coordinate,
        asAResume: Bool = false,
        logsEveryOutcome: Bool = false,
        from origin: PositionOrigin? = nil
    ) async {
        await evaluate(position: position, asAResume: asAResume, logsEveryOutcome: logsEveryOutcome, from: origin)
        await refreshRegions(around: position)
    }

    func handle(
        _ fix: PositionFix,
        maximumAge: TimeInterval = AutoLiveActivityRules.maximumPositionAge,
        logsEveryOutcome: Bool = false,
        from origin: PositionOrigin? = nil
    ) async {
        guard trusts(fix, maximumAge: maximumAge) else {
            if logsEveryOutcome {
                logUntrusted(fix, maximumAge: maximumAge)
            }
            await refreshRegions(around: fix.coordinate)
            return
        }
        cannotFindPosition = false
        await handle(fix.coordinate, logsEveryOutcome: logsEveryOutcome, from: origin)
    }
}
