import Testing
@testable import RATPCore

struct StationRegionPlanTests {
    private let origin = Coordinate(48.8500, 2.3500)

    private func stations(count: Int) -> [Station] {
        (1...count).map { index in
            Station(
                id: "s\(index)",
                name: "Station \(index)",
                coordinate: Coordinate(48.8500 + Double(index) * 0.001, 2.3500),
                lines: []
            )
        }
    }

    @Test func watchesTheNearestStationsAndARefreshAreaWithinTheSystemLimit() {
        let catalog = StationCatalog(stations: stations(count: 30).reversed())

        let regions = StationRegionPlan.regions(around: origin, stopStation: nil, catalog: catalog)

        #expect(regions.count == 19)
        #expect(regions.prefix(18).map(\.id) == (1...18).map { "arrival:s\($0)" })
        #expect(regions.prefix(18).allSatisfy { $0.radiusMeters == 150 })
    }

    @Test func addsTheStopAreaOfTheShownStationWithoutGoingOverTwentyRegions() {
        let all = stations(count: 30)
        let catalog = StationCatalog(stations: all)

        let regions = StationRegionPlan.regions(around: origin, stopStation: all[25], catalog: catalog)

        #expect(regions.count == StationRegionPlan.maximumRegions)
        #expect(regions.contains(WatchedRegion(id: "stop:s26", center: all[25].coordinate, radiusMeters: 250)))
    }

    @Test func refreshesTheRegionsBeforeThePhoneCanReachAStationThatIsNotWatched() {
        let all = stations(count: 30)
        let catalog = StationCatalog(stations: all)

        let refresh = StationRegionPlan.regions(around: origin, stopStation: nil, catalog: catalog).last

        let eighteenth = origin.distance(to: all[17].coordinate)
        #expect(refresh?.id == "refresh")
        #expect(refresh?.center == origin)
        #expect(refresh.map { abs($0.radiusMeters - (eighteenth - 150)) < 0.001 } == true)
    }

    @Test func keepsARefreshAreaLargeEnoughToBeReliable() {
        let catalog = StationCatalog(stations: [Station(id: "s", name: "S", coordinate: origin, lines: [])])

        let refresh = StationRegionPlan.regions(around: origin, stopStation: nil, catalog: catalog).last

        #expect(refresh?.radiusMeters == StationRegionPlan.minimumRefreshRadiusMeters)
    }

    @Test func readsTheStationOfAnArrivalRegion() {
        #expect(WatchedRegion.arrivalStationId(inRegionId: "arrival:IDFM:71264") == "IDFM:71264")
        #expect(WatchedRegion.arrivalStationId(inRegionId: "stop:IDFM:71264") == nil)
        #expect(WatchedRegion.arrivalStationId(inRegionId: "refresh") == nil)
    }

    @Test func trustsTheEnteredArrivalRegionWhenTheLastPositionIsOutsideIt() {
        let station = Station(id: "s", name: "S", coordinate: origin, lines: [])
        let catalog = StationCatalog(stations: [station])
        let insideTheArea = Coordinate(48.8505, 2.3500)
        let outsideTheArea = Coordinate(48.8520, 2.3500)

        let inside = WatchedRegion.position(
            afterEnteringRegionId: "arrival:s", lastKnownPosition: insideTheArea, catalog: catalog
        )
        let outside = WatchedRegion.position(
            afterEnteringRegionId: "arrival:s", lastKnownPosition: outsideTheArea, catalog: catalog
        )
        let unknown = WatchedRegion.position(
            afterEnteringRegionId: "arrival:s", lastKnownPosition: nil, catalog: catalog
        )

        #expect(inside == insideTheArea)
        #expect(outside == origin)
        #expect(unknown == origin)
    }

    @Test func usesTheLastPositionForEveryOtherRegionEvent() {
        let catalog = StationCatalog(stations: [Station(id: "s", name: "S", coordinate: origin, lines: [])])
        let last = Coordinate(48.8600, 2.3500)
        let position = { (id: String?, known: Coordinate?) in
            WatchedRegion.position(afterEnteringRegionId: id, lastKnownPosition: known, catalog: catalog)
        }

        #expect(position("refresh", last) == last)
        #expect(position(nil, last) == last)
        #expect(position(nil, nil) == nil)
    }
}
