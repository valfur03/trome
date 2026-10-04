import Foundation
import Synchronization
import Testing
@testable import TROMECore

@MainActor
final class StubArrivalNotifier: ArrivalNotifier {
    private(set) var authorizationRequestCount = 0
    private(set) var notified: [Station] = []
    private(set) var withdrawCount = 0
    var isRefusedByTheRider = false

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func notify(_ station: Station) async {
        guard !isRefusedByTheRider else { return }
        notified.append(station)
    }

    func withdraw() {
        withdrawCount += 1
    }
}

@MainActor
final class StubRegionWatcher: StationRegionWatcher {
    private(set) var watched: [[WatchedRegion]] = []

    func watch(_ regions: [WatchedRegion]) async {
        watched.append(regions)
    }
}

@MainActor
final class StubLocationKeeper: BackgroundLocationKeeper {
    private(set) var isKeeping = false

    func begin() {
        isKeeping = true
    }

    func end() {
        isKeeping = false
    }
}

@MainActor
final class StubLocationPermission: LocationPermission {
    var authorization: LocationAuthorization = .authorized
    var isAskingAlways = false
    private var alwaysQuestionWaiters: [CheckedContinuation<Void, Never>] = []

    var isWaitingForAlwaysQuestion: Bool {
        !alwaysQuestionWaiters.isEmpty
    }

    func requestAuthorization() async -> LocationAuthorization {
        authorization
    }

    func waitForAlwaysQuestion() async {
        guard isAskingAlways else { return }
        await withCheckedContinuation { alwaysQuestionWaiters.append($0) }
    }

    func answerAlwaysQuestion() {
        isAskingAlways = false
        alwaysQuestionWaiters.forEach { $0.resume() }
        alwaysQuestionWaiters = []
    }
}

final class TestClock: Sendable {
    static let refreshInterval: Duration = .seconds(30)
    private let date = Mutex(Date(timeIntervalSince1970: 1_000_000))
    private let firingLimit = Mutex<TimeInterval>(0)

    var now: Date {
        date.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    func letTimersFire(upTo seconds: TimeInterval = .infinity) {
        firingLimit.withLock { $0 = seconds }
    }

    func sleep(for duration: Duration) async throws {
        let seconds = TimeInterval(duration.components.seconds)
        guard duration != Self.refreshInterval, seconds <= firingLimit.withLock({ $0 }) else {
            try await Task.sleep(for: .seconds(3_600))
            return
        }
        try await Task.sleep(for: .milliseconds(20))
        advance(by: TimeInterval(duration.components.seconds))
    }
}

@MainActor
struct AutoLiveActivityModelTests {
    typealias Places = AutoTestPlaces
    let gps: ControlledLocationProvider
    let client = StubStationLiveActivityClient()
    let notifier = StubArrivalNotifier()
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

    func makeModel(catalog: StationCatalog = Places.catalog) -> AutoLiveActivityModel {
        let model = makeModel(locationService: locationService, keeper: keeper, catalog: catalog)
        locationService.start()
        return model
    }

    private func makeModel(
        locationService: LocationService,
        keeper: StubLocationKeeper,
        catalog: StationCatalog = Places.catalog
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
                notifier: notifier,
                regionWatcher: watcher,
                locationKeeper: keeper,
                liveActivityRemovals: removals
            ),
            configuration: .init(store: AutoLiveActivityStore(storage: storage), now: now, sleep: sleep)
        )
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func wake(_ model: AutoLiveActivityModel, at position: Coordinate) async {
        let fix = PositionFix(coordinate: position, accuracyMeters: 10, timestamp: clock.now)
        await model.handleRegionEvent(enteredRegionId: nil, lastKnownFix: fix)
    }

    func activate(_ model: AutoLiveActivityModel) async {
        model.setAppPhase(.active)
        await model.appDidBecomeActive()
    }

    func arrive(at position: Coordinate, in model: AutoLiveActivityModel) async {
        await activate(model)
        gps.report(position)
        await waitUntil { client.isShowing && keeper.isKeeping }
    }

    @Test func startsTheLiveActivityWhenThePhoneArrivesWhileTheAppIsOnScreen() async {
        let model = makeModel()

        await arrive(at: Places.fiftyMetersFromA, in: model)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
        #expect(keeper.isKeeping)
        #expect(notifier.notified.isEmpty)
    }

    @Test func notifiesWhenThePhoneArrivesWhileTheAppIsNotOnScreen() async {
        let model = makeModel()

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !notifier.notified.isEmpty }

        #expect(notifier.notified == [Places.stationA])
        #expect(client.started.isEmpty)
        withExtendedLifetime(model) {}
    }

    @Test func startsTheLiveActivityOfTheTappedNotificationOnceTheAppIsOnScreen() async {
        let model = makeModel()

        await model.notificationTapped(stationId: "b")
        #expect(client.started.isEmpty)
        await activate(model)

        #expect(client.started.map(\.stationName) == ["Station B"])
        #expect(model.shownStation == Places.stationB)
    }

    @Test func switchesStationInsteadOfShowingASecondLiveActivity() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        gps.report(Places.atB)
        await waitUntil { client.updates.last?.stationName == "Station B" }

        #expect(model.shownStation == Places.stationB)
        #expect(client.started.count == 1)
        #expect(client.updates.last?.stationName == "Station B")
        #expect(notifier.notified.isEmpty)
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
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await waitUntil { client.endCount == 1 && !keeper.isKeeping }

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
        #expect(notifier.notified.isEmpty)
    }

    @Test func watchesTheStationsAroundTheRealPosition() async {
        let model = makeModel()

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }

        let ids = watcher.watched.last?.map(\.id) ?? []
        #expect(ids == ["arrival:a", "arrival:b", "stop:a", "refresh"])
        withExtendedLifetime(model) {}
    }

    @Test func notifiesAndWatchesTheStationsAroundAPositionFromRegionMonitoring() async {
        let model = makeModel()

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
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

    @Test func keepsTheTappedLiveActivityWhenTheAppComesBackWithAPositionFromBefore() async {
        let model = makeModel()
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { locationService.position != nil }

        await model.notificationTapped(stationId: "a")
        await activate(model)

        #expect(model.shownStation == Places.stationA)
        #expect(client.endCount == 0)
    }

    @Test func watchesTheStationsAgainWhenTheAppComesBackWithoutAMove() async {
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }

        await activate(model)

        #expect(watcher.watched.count == 2)
    }
}
