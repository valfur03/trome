import Foundation
import Synchronization
import Testing
@testable import TROMECore

/// The only path from the core to the notifications of iOS: it can ask the question, and send nothing.
@MainActor
final class StubNotificationPermission: NotificationPermission {
    private(set) var authorizationRequestCount = 0

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }
}

@MainActor
final class StubRegionWatcher: StationRegionWatcher {
    private(set) var watched: [[WatchedRegion]] = []
    /// What iOS holds for each area, as the test sets it.
    var held: [String: RegionHold] = [:]
    private(set) var holdsReadCount = 0

    func watch(_ regions: [WatchedRegion]) async {
        watched.append(regions)
    }

    func holds() async -> [String: RegionHold] {
        holdsReadCount += 1
        return held
    }
}

@MainActor
final class StubLocationKeeper: BackgroundLocationKeeper {
    private(set) var isKeeping = false
    var onPosition: (@MainActor (PositionFix) -> Void)?

    /// A position of the standard updates that keep the app running, as iOS gives it while it runs.
    func report(_ fix: PositionFix) {
        guard isKeeping else { return }
        onPosition?(fix)
    }

    func begin() {
        isKeeping = true
    }

    func end() {
        isKeeping = false
    }
}

final class TestClock: Sendable {
    static let refreshInterval: Duration = .seconds(30)
    private let date = Mutex(Date(timeIntervalSince1970: 1_000_000))
    private let firingLimit = Mutex<TimeInterval>(0)
    private let heldTimers = Mutex<Set<TimeInterval>>([])

    var now: Date {
        date.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    func letTimersFire(upTo seconds: TimeInterval = .infinity) {
        firingLimit.withLock { $0 = seconds }
    }

    /// Keeps the timers of this length from firing. A timer that may fire ends after a few milliseconds of real
    /// time, so one that races a fake answer (the wait for a slow answer) wins on a busy machine.
    func holdTimers(of seconds: TimeInterval) {
        heldTimers.withLock { _ = $0.insert(seconds) }
    }

    func sleep(for duration: Duration) async throws {
        let seconds = TimeInterval(duration.components.seconds)
        let isHeld = heldTimers.withLock { $0.contains(seconds) }
        guard duration != Self.refreshInterval, !isHeld, seconds <= firingLimit.withLock({ $0 }) else {
            try await Task.sleep(for: .seconds(3_600))
            return
        }
        try await Task.sleep(for: .milliseconds(20))
        advance(by: TimeInterval(duration.components.seconds))
    }
}

@MainActor
@Suite(.bounded)
struct AutoLiveActivityModelTests {
    typealias Places = AutoTestPlaces
    let gps: ControlledLocationProvider
    let client = StubStationLiveActivityClient()
    let notifications = StubNotificationPermission()
    let watcher = StubRegionWatcher()
    let keeper = StubLocationKeeper()
    let removals = StubLiveActivityRemovals()
    let permission = StubLocationPermission()
    let provider = StubDeparturesProvider()
    let storage = InMemoryKeyValueStore()
    let clock = TestClock()
    let locationService: LocationService
    let screenTrains: NextTrainsModel
    let automaticMode: AutomaticModeModel
    let wakeLog = WakeLog(storage: InMemoryKeyValueStore())

    init() {
        let clock = clock
        gps = ControlledLocationProvider(now: { clock.now })
        locationService = LocationService(
            realProvider: gps,
            sourceStore: LocationSourceStore(storage: InMemoryKeyValueStore())
        )
        screenTrains = NextTrainsModel(
            provider: provider,
            now: { clock.now },
            sleep: { try await clock.sleep(for: $0) }
        )
        automaticMode = AutomaticModeModel(
            store: AutomaticModeStore(storage: InMemoryKeyValueStore()),
            now: { clock.now },
            sleep: { try await clock.sleep(for: $0) }
        )
    }

    func makeModel(catalog: StationCatalog = Places.catalog, silentStart: SilentStart? = nil) -> AutoLiveActivityModel {
        let model = makeModel(
            locationService: locationService, keeper: keeper, catalog: catalog, silentStart: silentStart
        )
        locationService.start()
        return model
    }

    private func makeModel(
        locationService: LocationService,
        keeper: StubLocationKeeper,
        catalog: StationCatalog = Places.catalog,
        silentStart: SilentStart? = nil
    ) -> AutoLiveActivityModel {
        let clock = clock
        let now: @Sendable () -> Date = { clock.now }
        let sleep: @Sendable (Duration) async throws -> Void = { try await clock.sleep(for: $0) }
        return AutoLiveActivityModel(
            catalog: catalog,
            liveActivity: StationLiveActivityModel(client: client, now: now),
            inputs: .init(
                locationService: locationService,
                permission: permission,
                screenTrains: screenTrains,
                liveActivityTrains: NextTrainsModel(provider: provider, now: now, sleep: sleep),
                automaticMode: automaticMode
            ),
            services: .init(
                notifications: notifications,
                regionWatcher: watcher,
                locationKeeper: keeper,
                liveActivityChanges: removals,
                wakeLog: wakeLog,
                silentStart: silentStart
            ),
            configuration: .init(store: AutoLiveActivityStore(storage: storage), now: now, sleep: sleep)
        )
    }

    /// The station of each arrival in the background that started no Live Activity, oldest first: each one writes
    /// its line of the wake log, with its cause, and no notification.
    var arrivalsWithNoStart: [String] {
        wakeLog.entries.reversed().filter { $0.kind == .silentStart }.compactMap { entry in
            guard entry.text.hasPrefix("No start at "), let end = entry.text.range(of: ", no notification: ") else {
                return nil
            }
            return String(entry.text[entry.text.index(entry.text.startIndex, offsetBy: 12)..<end.lowerBound])
        }
    }

    func wake(_ model: AutoLiveActivityModel, at position: Coordinate) async {
        let fix = PositionFix(coordinate: position, accuracyMeters: 10, timestamp: clock.now)
        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: fix)
    }

    /// As in the app, the main screen follows the position again once the app is on screen (`NearestStationModel`).
    func activate(_ model: AutoLiveActivityModel) async {
        model.setAppPhase(.active)
        locationService.start()
        await model.appDidBecomeActive()
    }

    func arrive(
        at position: Coordinate,
        in model: AutoLiveActivityModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await activate(model)
        gps.report(position)
        await waitUntil(sourceLocation: sourceLocation) { client.isShowing && keeper.isKeeping }
    }

    @Test func startsTheLiveActivityWhenThePhoneArrivesWhileTheAppIsOnScreen() async {
        let model = makeModel()

        await arrive(at: Places.fiftyMetersFromA, in: model)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
        #expect(keeper.isKeeping)
        #expect(arrivalsWithNoStart.isEmpty)
    }

    @Test func startsNothingAndSaysWhyWhenThePhoneArrivesWhileTheAppIsNotOnScreen() async {
        let model = makeModel()

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !arrivalsWithNoStart.isEmpty }

        #expect(arrivalsWithNoStart == [Places.stationA.name])
        #expect(client.started.isEmpty)
        withExtendedLifetime(model) {}
    }

    @Test func switchesStationInsteadOfShowingASecondLiveActivity() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        gps.report(Places.atB)
        await waitUntil { client.updates.last?.stationName == "Station B" }

        #expect(model.shownStation == Places.stationB)
        #expect(client.started.count == 1)
        #expect(client.updates.last?.stationName == "Station B")
        #expect(arrivalsWithNoStart.isEmpty)
    }

    @Test func endsTheLiveActivityWhenThePhoneMovesAway() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 && !keeper.isKeeping }

        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func endsTheLiveActivityAfterTheMaximumDurationWithoutAnyMove() async {
        clock.letTimersFire()
        let model = makeModel()
        await activate(model)
        gps.report(Places.fiftyMetersFromA)

        // The timer ends it 20 ms after the start, so wait for what stays: a start, then an end.
        await waitUntil { client.started.count == 1 && client.endCount == 1 && !keeper.isKeeping }

        #expect(client.endCount == 1)
        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func doesNotStartAgainAfterAStopByHandInTheSameArea() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.stopByHand()
        gps.report(Places.twoHundredMetersFromA)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { locationService.position == Places.fiftyMetersFromA }
        await activate(model)

        #expect(client.started.count == 1)
        #expect(client.isShowing == false)
    }

    @Test func startsByHandForAStationFarFromThePhoneAndKeepsIt() async {
        let model = makeModel()
        await activate(model)
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { locationService.position != nil }

        await model.startByHand(Places.stationB)
        gps.report(Places.fourHundredMetersFromA)
        await activate(model)

        #expect(model.shownStation == Places.stationB)
        #expect(client.endCount == 0)
    }

    @Test func forgetsALiveActivityDismissedFromTheLockScreen() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        client.isShowing = false
        await activate(model)

        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func remembersTheShownStationAfterARelaunch() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        let relaunched = makeModel()

        #expect(relaunched.shownStation == Places.stationA)
    }

    @Test func followsThePositionAgainWhenRelaunchedWhileTheLiveActivityShows() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        let relaunchedGPS = ControlledLocationProvider(now: { [clock] in clock.now })
        let relaunchedKeeper = StubLocationKeeper()

        let relaunched = makeModel(
            locationService: LocationService(
                realProvider: relaunchedGPS,
                sourceStore: LocationSourceStore(storage: InMemoryKeyValueStore())
            ),
            keeper: relaunchedKeeper
        )
        #expect(relaunchedKeeper.isKeeping)
        relaunchedGPS.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 && !relaunchedKeeper.isKeeping }

        #expect(client.endCount == 1)
        #expect(relaunched.shownStation == nil)
        #expect(relaunchedKeeper.isKeeping == false)
        withExtendedLifetime(model) {}
    }

    @Test func startsTheLiveActivityWhenTheFirstPositionComesBeforeTheAppFinishesComingOnScreen() async {
        let model = makeModel()

        model.setAppPhase(.active)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.isShowing }
        await model.appDidBecomeActive()

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(arrivalsWithNoStart.isEmpty)
    }

    @Test func watchesTheStationsAroundTheRealPosition() async {
        let model = makeModel()

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }

        let ids = watcher.watched.last?.map(\.id) ?? []
        #expect(ids == ["arrival:a", "arrival:b", "stop:a", "refresh"])
        withExtendedLifetime(model) {}
    }

    @Test func arrivesAndWatchesTheStationsAroundAPositionFromRegionMonitoring() async {
        let model = makeModel()

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(arrivalsWithNoStart == [Places.stationA.name])
        #expect(watcher.watched.last?.map(\.id) == ["arrival:a", "arrival:b", "stop:a", "refresh"])
    }

    @Test func stopsWatchingRealStationsWhileAFakePositionIsOn() async {
        let model = makeModel()
        await activate(model)

        locationService.use(.fake(Places.stationA.fakePosition))
        await waitUntil { client.isShowing }
        await wake(model, at: Places.atB)

        #expect(watcher.watched.last == [])
        #expect(model.shownStation == Places.stationA)
    }

    @Test func watchesTheStationsAgainWhenTheAppComesBackWithoutAMove() async {
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }

        await activate(model)

        #expect(watcher.watched.count == 2)
    }
}
