import Testing
@testable import RATPCore

@MainActor
private final class MockLocationProvider: LocationProvider {
    struct Failure: Error {}

    var authorization: LocationAuthorization
    var answerToRequest: LocationAuthorization
    var coordinate: Coordinate?
    private(set) var requestCount = 0

    init(
        authorization: LocationAuthorization,
        answerToRequest: LocationAuthorization = .authorized,
        coordinate: Coordinate? = nil
    ) {
        self.authorization = authorization
        self.answerToRequest = answerToRequest
        self.coordinate = coordinate
    }

    func requestAuthorization() async -> LocationAuthorization {
        requestCount += 1
        authorization = answerToRequest
        return answerToRequest
    }

    func currentCoordinate() async throws -> Coordinate {
        guard let coordinate else { throw Failure() }
        return coordinate
    }
}

@MainActor
struct NearestStationModelTests {
    private let nation = Station(
        id: "nation",
        name: "Nation",
        coordinate: Coordinate(latitude: 48.8483, longitude: 2.3960),
        lines: [TransitLine(mode: .metro, name: "1"), TransitLine(mode: .rer, name: "A")]
    )
    private let nearNation = Coordinate(latitude: 48.8490, longitude: 2.3960)
    private let farFromNation = Coordinate(latitude: 48.9500, longitude: 2.3960)

    private func makeModel(_ provider: MockLocationProvider) -> NearestStationModel {
        NearestStationModel(locationProvider: provider, catalog: StationCatalog(stations: [nation]))
    }

    @Test func asksForPermissionTheFirstTimeThenFindsTheStation() async {
        let provider = MockLocationProvider(authorization: .notDetermined, coordinate: nearNation)
        let model = makeModel(provider)

        await model.refresh()

        #expect(provider.requestCount == 1)
        let distance = nearNation.distance(to: nation.coordinate)
        #expect(model.state == .found(NearbyStation(station: nation, distanceMeters: distance)))
    }

    @Test func doesNotAskAgainOncePermissionIsGranted() async {
        let provider = MockLocationProvider(authorization: .authorized, coordinate: nearNation)
        let model = makeModel(provider)

        await model.refresh()

        #expect(provider.requestCount == 0)
    }

    @Test func asksAgainNextTimeWhenTheUserHasNotDecided() async {
        let provider = MockLocationProvider(authorization: .notDetermined, answerToRequest: .notDetermined)
        let model = makeModel(provider)

        await model.refresh()
        #expect(model.state == .permissionUndecided)

        await model.refresh()
        #expect(provider.requestCount == 2)
    }

    @Test func reportsADeniedPermissionWithoutAskingAgain() async {
        let provider = MockLocationProvider(authorization: .denied)
        let model = makeModel(provider)

        await model.refresh()

        #expect(model.state == .permissionDenied)
        #expect(provider.requestCount == 0)
    }

    @Test func reportsAPermissionDeniedAtTheRequest() async {
        let provider = MockLocationProvider(authorization: .notDetermined, answerToRequest: .denied)
        let model = makeModel(provider)

        await model.refresh()

        #expect(model.state == .permissionDenied)
    }

    @Test func reportsWhenNoStationIsWithinWalkingDistance() async {
        let provider = MockLocationProvider(authorization: .authorized, coordinate: farFromNation)
        let model = makeModel(provider)

        await model.refresh()

        #expect(model.state == .noStationNearby)
    }

    @Test func reportsWhenThePositionIsUnavailable() async {
        let provider = MockLocationProvider(authorization: .authorized, coordinate: nil)
        let model = makeModel(provider)

        await model.refresh()

        #expect(model.state == .locationUnavailable)
    }

    @Test func followsTheNewPositionOnTheNextRefresh() async {
        let provider = MockLocationProvider(authorization: .authorized, coordinate: nearNation)
        let model = makeModel(provider)
        await model.refresh()

        provider.coordinate = farFromNation
        await model.refresh()

        #expect(model.state == .noStationNearby)
    }
}
