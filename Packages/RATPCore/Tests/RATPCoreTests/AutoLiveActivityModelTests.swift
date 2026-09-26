import Foundation
import Synchronization
import Testing
@testable import RATPCore

@MainActor
private final class StubArrivalNotifier: ArrivalNotifier {
    private(set) var authorizationRequestCount = 0
    private(set) var notified: [Station] = []
    private(set) var withdrawCount = 0

    func requestAuthorization() async {
        authorizationRequestCount += 1
    }

    func notify(_ station: Station) async {
        notified.append(station)
    }

    func withdraw() {
        withdrawCount += 1
    }
}

@MainActor
private final class StubRegionWatcher: StationRegionWatcher {
    private(set) var watched: [[WatchedRegion]] = []

    func watch(_ regions: [WatchedRegion]) async {
        watched.append(regions)
    }
}

@MainActor
private final class StubLocationKeeper: BackgroundLocationKeeper {
    private(set) var isKeeping = false

    func begin() {
        isKeeping = true
    }

    func end() {
        isKeeping = false
    }
}

@MainActor
private final class StubLocationPermission: LocationPermission {
    var authorization: LocationAuthorization = .authorized

    func requestAuthorization() async -> LocationAuthorization {
        authorization
    }
}

private final class TestClock: Sendable {
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
    private typealias Places = AutoTestPlaces
    private let gps = ControlledLocationProvider()
    private let client = StubStationLiveActivityClient()
    private let notifier = StubArrivalNotifier()
    private let watcher = StubRegionWatcher()
    private let keeper = StubLocationKeeper()
    private let permission = StubLocationPermission()
    private let provider = StubDeparturesProvider()
    private let storage = InMemoryKeyValueStore()
    private let clock = TestClock()
    private let locationService: LocationService
    private let screenTrains: NextTrainsModel

    init() {
        locationService = LocationService(
            realProvider: gps,
            sourceStore: LocationSourceStore(storage: InMemoryKeyValueStore())
        )
        let clock = clock
        screenTrains = NextTrainsModel(
            provider: provider,
            now: { clock.now },
            sleep: { try await clock.sleep(for: $0) }
        )
    }

    private func makeModel() -> AutoLiveActivityModel {
        let model = makeModel(locationService: locationService, keeper: keeper)
        locationService.start()
        return model
    }

    private func makeModel(locationService: LocationService, keeper: StubLocationKeeper) -> AutoLiveActivityModel {
        let clock = clock
        let now: @Sendable () -> Date = { clock.now }
        let sleep: @Sendable (Duration) async throws -> Void = { try await clock.sleep(for: $0) }
        return AutoLiveActivityModel(
            catalog: Places.catalog,
            liveActivity: StationLiveActivityModel(client: client, now: now),
            inputs: .init(
                locationService: locationService,
                permission: permission,
                screenTrains: screenTrains,
                liveActivityTrains: NextTrainsModel(provider: provider, now: now, sleep: sleep)
            ),
            services: .init(notifier: notifier, regionWatcher: watcher, locationKeeper: keeper),
            configuration: .init(store: AutoLiveActivityStore(storage: storage), now: now, sleep: sleep)
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func arrive(at position: Coordinate, in model: AutoLiveActivityModel) async {
        await model.setAppActive(true)
        gps.report(position)
        await waitUntil { client.isShowing }
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
        await model.setAppActive(true)

        #expect(client.started.map(\.stationName) == ["Station B"])
        #expect(model.shownStation == Places.stationB)
    }

    @Test func switchesStationInsteadOfShowingASecondLiveActivity() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        gps.report(Places.atB)
        await waitUntil { model.shownStation == Places.stationB }

        #expect(client.started.count == 1)
        #expect(client.updates.last?.stationName == "Station B")
        #expect(notifier.notified.isEmpty)
    }

    @Test func endsTheLiveActivityWhenThePhoneMovesAway() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 }

        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func endsTheLiveActivityAfterTheMaximumDurationWithoutAnyMove() async {
        clock.letTimersFire()
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await waitUntil { client.endCount == 1 }

        #expect(client.endCount == 1)
        #expect(model.shownStation == nil)
    }

    @Test func doesNotStartAgainAfterAStopByHandInTheSameArea() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.stopByHand()
        gps.report(Places.twoHundredMetersFromA)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { locationService.position == Places.fiftyMetersFromA }
        await model.setAppActive(true)

        #expect(client.started.count == 1)
        #expect(client.isShowing == false)
    }

    @Test func startsByHandForAStationFarFromThePhoneAndKeepsIt() async {
        let model = makeModel()
        await model.setAppActive(true)
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { locationService.position != nil }

        await model.startByHand(Places.stationB)
        gps.report(Places.fourHundredMetersFromA)
        await model.setAppActive(true)

        #expect(model.shownStation == Places.stationB)
        #expect(client.endCount == 0)
    }

    @Test func forgetsALiveActivityDismissedFromTheLockScreen() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        client.isShowing = false
        await model.setAppActive(true)

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
        let relaunchedGPS = ControlledLocationProvider()
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
        await waitUntil { client.endCount == 1 }

        #expect(client.endCount == 1)
        #expect(relaunched.shownStation == nil)
        #expect(relaunchedKeeper.isKeeping == false)
        withExtendedLifetime(model) {}
    }

    @Test func feedsTheLiveActivityAgainWhenRelaunchedWhileItShows() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { !client.updates.isEmpty }
        let callCount = provider.callCount

        let relaunched = makeModel()
        await waitUntil { provider.callCount > callCount }

        #expect(provider.callCount > callCount)
        withExtendedLifetime((model, relaunched)) {}
    }

    @Test func asksForNotificationsOnceLocationIsAllowed() async {
        permission.authorization = .notDetermined
        let model = makeModel()
        await model.setAppActive(true)
        #expect(notifier.authorizationRequestCount == 0)

        permission.authorization = .authorized
        await model.setAppActive(true)
        await model.setAppActive(true)

        #expect(notifier.authorizationRequestCount == 1)
    }

    @Test func feedsTheLiveActivityWithTheTrainsOfItsOwnStation() async {
        provider.answer(.failure(.unreachable), for: Places.stationA)
        let model = makeModel()

        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.updates.contains { $0.trains == .noData } }

        #expect(client.updates.last?.stationName == "Station A")
        #expect(client.updates.last?.trains == .noData)
    }

    @Test func feedsTheLiveActivityItselfOnceTheScreenStopsUpdatingItsStation() async {
        let model = makeModel()
        let screen = Task { await screenTrains.keepUpdated(for: Places.stationA) }
        await waitUntil { provider.callCount == 1 }
        await arrive(at: Places.fiftyMetersFromA, in: model)
        #expect(provider.callCount == 1)

        screen.cancel()
        await waitUntil { provider.callCount == 2 }

        #expect(provider.callCount == 2)
    }

    @Test func keepsFeedingTheLiveActivityWhileTheAppIsInTheBackground() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await model.setAppActive(false)
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount >= callCount + 2 }

        #expect(provider.callCount >= callCount + 2)
        #expect(client.isShowing)
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

        await model.handleMonitoredPosition(Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
        #expect(watcher.watched.last?.map(\.id) == ["arrival:a", "arrival:b", "stop:a", "refresh"])
    }

    @Test func stopsWatchingRealStationsWhileAFakePositionIsOn() async {
        let model = makeModel()
        await model.setAppActive(true)

        locationService.use(.fake(Places.stationA.fakePosition))
        await waitUntil { client.isShowing }
        await model.handleMonitoredPosition(Places.atB)

        #expect(watcher.watched.last == [])
        #expect(model.shownStation == Places.stationA)
    }

    @Test func keepsTheTappedLiveActivityWhenTheAppComesBackWithAPositionFromBefore() async {
        let model = makeModel()
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { locationService.position != nil }

        await model.notificationTapped(stationId: "a")
        await model.setAppActive(true)

        #expect(model.shownStation == Places.stationA)
        #expect(client.endCount == 0)
    }

    @Test func watchesTheStationsAgainWhenTheAppComesBackWithoutAMove() async {
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }

        await model.setAppActive(true)

        #expect(watcher.watched.count == 2)
    }
}
