import Foundation
import Testing
@testable import TROMECore

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

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func fix(at coordinate: Coordinate, accuracy: Double = 10, secondsAgo: TimeInterval = 0) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: accuracy, timestamp: now.addingTimeInterval(-secondsAgo))
    }

    @Test func trustsTheEnteredArrivalRegionWhenTheLastPositionIsOutsideItOrRough() {
        let station = Station(id: "s", name: "S", coordinate: origin, lines: [])
        let catalog = StationCatalog(stations: [station])
        let insideTheArea = Coordinate(48.8505, 2.3500)
        let outsideTheArea = Coordinate(48.8520, 2.3500)
        let fixAfterEntering = { (known: PositionFix?) in
            WatchedRegion.fix(afterEnteringRegionId: "arrival:s", lastKnownFix: known, now: now, catalog: catalog)
        }
        let atTheStation = fix(at: origin, accuracy: 0)

        #expect(fixAfterEntering(fix(at: insideTheArea, secondsAgo: 120)) == fix(at: insideTheArea, secondsAgo: 120))
        #expect(fixAfterEntering(fix(at: outsideTheArea)) == atTheStation)
        #expect(fixAfterEntering(fix(at: insideTheArea, accuracy: 500)) == atTheStation)
        #expect(fixAfterEntering(fix(at: insideTheArea, secondsAgo: 121)) == atTheStation)
        #expect(fixAfterEntering(nil) == atTheStation)
    }

    @Test func usesTheLastRecentPositionForEveryOtherRegionEvent() {
        let catalog = StationCatalog(stations: [Station(id: "s", name: "S", coordinate: origin, lines: [])])
        let last = Coordinate(48.8600, 2.3500)
        let fixAfter = { (id: String?, known: PositionFix?) in
            WatchedRegion.fix(afterEnteringRegionId: id, lastKnownFix: known, now: now, catalog: catalog)
        }

        let roughRecentFix = fix(at: last, accuracy: 500, secondsAgo: 120)

        #expect(fixAfter("refresh", fix(at: last)) == fix(at: last))
        #expect(fixAfter(nil, roughRecentFix) == roughRecentFix)
        #expect(fixAfter(nil, fix(at: last, secondsAgo: 121)) == nil)
        #expect(fixAfter(nil, nil) == nil)
    }
}

extension StationRegionPlanTests {
    @Test func namesEachRegionForTheWakeLog() {
        let catalog = AutoTestPlaces.catalog

        #expect(WatchedRegion.label(ofId: "arrival:a", catalog: catalog) == "Station A")
        #expect(WatchedRegion.label(ofId: "stop:b", catalog: catalog) == "stop area of Station B")
        #expect(WatchedRegion.label(ofId: "refresh", catalog: catalog) == "area around you")
        #expect(WatchedRegion.label(ofId: "arrival:unknown", catalog: catalog) == "arrival:unknown")
    }

    @Test func summarizesTheWatchedStationsFromTheNearestToTheFarthest() {
        let all = stations(count: 3)
        let catalog = StationCatalog(stations: all)
        let regions = StationRegionPlan.regions(around: origin, stopStation: nil, catalog: catalog)

        let summary = WatchedRegion.summary(of: regions, around: origin, catalog: catalog)

        #expect(summary == "Watching 3 stations, from Station 1 (111 m) to Station 3 (333 m); area around you 200 m")
    }
}
