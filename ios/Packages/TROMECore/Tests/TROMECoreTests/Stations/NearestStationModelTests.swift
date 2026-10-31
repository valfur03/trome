import Foundation
import Synchronization
import Testing
@testable import TROMECore

@MainActor
private final class MockLocationPermission: LocationPermission {
    var authorization: LocationAuthorization
    var answerToRequest: LocationAuthorization
    private(set) var requestCount = 0

    init(authorization: LocationAuthorization, answerToRequest: LocationAuthorization = .authorized) {
        self.authorization = authorization
        self.answerToRequest = answerToRequest
    }

    func requestAuthorization() async -> LocationAuthorization {
        requestCount += 1
        authorization = answerToRequest
        return answerToRequest
    }

    func waitForAlwaysQuestion() async {}
}

@MainActor
struct NearestStationModelTests {
    private let gps = ControlledLocationProvider()
    private let nation = Station(
        id: "nation",
        name: "Nation",
        coordinate: Coordinate(48.8483, 2.3960),
        lines: [TransitLine(mode: .metro, name: "1"), TransitLine(mode: .rer, name: "A")]
    )
    private let nearNation = Coordinate(48.8490, 2.3960)
    private let farFromNation = Coordinate(48.9500, 2.3960)

    private static let neverTimesOut: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3_600))
    }
    private static let timesOutAtOnce: @Sendable (Duration) async throws -> Void = { _ in }

    private func makeModel(
        _ permission: MockLocationPermission,
        locationService: LocationService? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = neverTimesOut
    ) -> NearestStationModel {
        NearestStationModel(
            permission: permission,
            locationService: locationService ?? LocationService(realProvider: gps, sourceStore: nil),
            catalog: StationCatalog(stations: [nation]),
            sleep: sleep
        )
    }

    private func foundNation(from position: Coordinate) -> NearestStationState {
        .found(NearbyStation(station: nation, distanceMeters: position.distance(to: nation.coordinate)))
    }

    private func waitForState(
        _ expected: NearestStationState,
        in model: NearestStationModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await waitUntil(sourceLocation: sourceLocation) { model.state == expected }
    }

    @Test func asksForPermissionTheFirstTimeThenFindsTheStation() async {
        let permission = MockLocationPermission(authorization: .notDetermined)
        let model = makeModel(permission)

        await model.refresh()
        gps.report(nearNation)
        await waitForState(foundNation(from: nearNation), in: model)

        #expect(permission.requestCount == 1)
        #expect(model.state == foundNation(from: nearNation))
    }

    @Test func doesNotAskAgainOncePermissionIsGranted() async {
        let permission = MockLocationPermission(authorization: .authorized)
        let model = makeModel(permission)

        await model.refresh()

        #expect(permission.requestCount == 0)
    }

    @Test func asksAgainNextTimeWhenTheUserHasNotDecided() async {
        let permission = MockLocationPermission(authorization: .notDetermined, answerToRequest: .notDetermined)
        let model = makeModel(permission)

        await model.refresh()
        #expect(model.state == .permissionUndecided)

        await model.refresh()
        #expect(permission.requestCount == 2)
    }

    @Test func reportsADeniedPermissionWithoutAskingAgain() async {
        let permission = MockLocationPermission(authorization: .denied)
        let model = makeModel(permission)

        await model.refresh()

        #expect(model.state == .permissionDenied)
        #expect(permission.requestCount == 0)
    }

    @Test func reportsAPermissionDeniedAtTheRequest() async {
        let permission = MockLocationPermission(authorization: .notDetermined, answerToRequest: .denied)
        let model = makeModel(permission)

        await model.refresh()

        #expect(model.state == .permissionDenied)
    }

    @Test func reportsWhenNoStationIsWithinWalkingDistance() async {
        let model = makeModel(MockLocationPermission(authorization: .authorized))

        await model.refresh()
        gps.report(farFromNation)
        await waitForState(.noStationNearby, in: model)

        #expect(model.state == .noStationNearby)
    }

    @Test func reportsWhenThePositionIsUnavailable() async {
        let model = makeModel(MockLocationPermission(authorization: .authorized), sleep: Self.timesOutAtOnce)

        await model.refresh()
        #expect(model.state == .locating)

        await waitForState(.locationUnavailable, in: model)
        #expect(model.state == .locationUnavailable)
    }

    @Test func waitsTwentySecondsForThePositionByDefault() async {
        let waits = Mutex<[Duration]>([])
        let model = NearestStationModel(
            permission: MockLocationPermission(authorization: .authorized),
            locationService: LocationService(realProvider: gps, sourceStore: nil),
            catalog: StationCatalog(stations: [nation]),
            sleep: { duration in waits.withLock { $0.append(duration) } }
        )

        await model.refresh()
        await waitForState(.locationUnavailable, in: model)

        #expect(waits.withLock { $0 } == [.seconds(20)])
    }

    @Test func followsTheNewPosition() async {
        let model = makeModel(MockLocationPermission(authorization: .authorized))
        await model.refresh()
        gps.report(nearNation)
        await waitForState(foundNation(from: nearNation), in: model)

        gps.report(farFromNation)
        await waitForState(.noStationNearby, in: model)

        #expect(model.state == .noStationNearby)
    }

    @Test func showsTheStationWithARoughAndOldPosition() async {
        let model = makeModel(MockLocationPermission(authorization: .authorized))

        await model.refresh()
        gps.report(PositionFix(coordinate: nearNation, accuracyMeters: 1_000, timestamp: .distantPast))
        await waitForState(foundNation(from: nearNation), in: model)

        #expect(model.state == foundNation(from: nearNation))
    }

    @Test func usesTheFakePosition() async {
        let locationService = LocationService(
            realProvider: gps,
            sourceStore: LocationSourceStore(storage: InMemoryKeyValueStore())
        )
        locationService.use(.fake(FakePosition(name: "Near Nation", coordinate: nearNation)))
        let model = makeModel(MockLocationPermission(authorization: .authorized), locationService: locationService)

        await model.refresh()
        gps.report(farFromNation)
        await waitForState(foundNation(from: nearNation), in: model)

        #expect(model.state == foundNation(from: nearNation))
    }

    @Test func dropsTheOldStationWhenTheLocationSourceChanges() async {
        let locationService = LocationService(
            realProvider: gps,
            sourceStore: LocationSourceStore(storage: InMemoryKeyValueStore())
        )
        locationService.use(.fake(FakePosition(name: "Near Nation", coordinate: nearNation)))
        let model = makeModel(
            MockLocationPermission(authorization: .authorized),
            locationService: locationService,
            sleep: Self.timesOutAtOnce
        )
        await model.refresh()
        await waitForState(foundNation(from: nearNation), in: model)

        locationService.use(.realGPS)
        await waitForState(.locationUnavailable, in: model)
        #expect(model.state == .locationUnavailable)

        gps.report(farFromNation)
        await waitForState(.noStationNearby, in: model)
        #expect(model.state == .noStationNearby)
    }

    @Test func ignoresNewPositionsOncePermissionIsTurnedOff() async {
        let permission = MockLocationPermission(authorization: .authorized)
        let model = makeModel(permission)
        await model.refresh()
        gps.report(nearNation)
        await waitForState(foundNation(from: nearNation), in: model)

        permission.authorization = .denied
        await model.refresh()
        await waitForState(.permissionDenied, in: model)
        gps.report(farFromNation)
        await expectNever { model.state != .permissionDenied }

        #expect(model.state == .permissionDenied)
    }

    @Test func givesTheNearestStationNowOnceThePositionArrives() async {
        let model = makeModel(MockLocationPermission(authorization: .authorized))

        async let result = model.nearestStationNow()
        await waitForState(.locating, in: model)
        gps.report(nearNation)

        #expect(await result == .success(nation))
    }

    @Test func explainsWhyThereIsNoNearestStationNow() async {
        let denied = makeModel(MockLocationPermission(authorization: .denied))
        let undecided = makeModel(
            MockLocationPermission(authorization: .notDetermined, answerToRequest: .notDetermined)
        )
        let unavailable = makeModel(MockLocationPermission(authorization: .authorized), sleep: Self.timesOutAtOnce)

        #expect(await denied.nearestStationNow() == .failure(.permissionDenied))
        #expect(await undecided.nearestStationNow() == .failure(.permissionUndecided))
        #expect(await unavailable.nearestStationNow() == .failure(.locationUnavailable))
    }

    @Test func saysNoStationIsNearbyNow() async {
        let model = makeModel(MockLocationPermission(authorization: .authorized))

        async let result = model.nearestStationNow()
        await waitForState(.locating, in: model)
        gps.report(farFromNation)

        #expect(await result == .failure(.noStationNearby))
    }
}
