import Foundation
import Testing
@testable import TROMECore

/// The line that the Wake log writes when iOS sends an event for an area: a walk reads from it how far
/// from the station, and how late, iOS woke the app.
struct RegionEventTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func fix(at coordinate: Coordinate, accuracy: Double = 12, age: TimeInterval) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: accuracy, timestamp: now - age)
    }

    private func line(_ event: RegionEvent, _ fix: PositionFix?) -> String {
        event.wakeLine(phoneAt: fix, now: now, catalog: AutoTestPlaces.catalog)
    }

    @Test func saysWhereThePhoneWasForAnEntryWithAFreshPosition() {
        let line = line(.entered(regionId: "arrival:a"), fix(at: AutoTestPlaces.twoHundredMetersFromA, age: 4))

        #expect(line == "iOS: entered Station A (phone 200 m away, ±12 m, 4 s old)")
    }

    @Test func saysHowOldThePositionIsForAnEntryWithAnOldPosition() {
        let old = fix(at: AutoTestPlaces.fourHundredMetersFromA, accuracy: 65, age: 600)

        let line = line(.entered(regionId: "arrival:a"), old)

        #expect(line == "iOS: entered Station A (phone 400 m away, ±65 m, 600 s old)")
    }

    @Test func saysThatIOSGaveNoPositionForAnEntryWithNone() {
        #expect(line(.entered(regionId: "arrival:a"), nil) == "iOS: entered Station A (iOS gave no position)")
    }

    @Test func measuresAnExitFromTheCentreOfTheStationOfTheStopArea() {
        let line = line(.left(regionId: "stop:a"), fix(at: AutoTestPlaces.fourHundredMetersFromA, accuracy: 8, age: 0))

        #expect(line == "iOS: left stop area of Station A (phone 400 m away, ±8 m, 0 s old)")
    }

    @Test func measuresTheExitOfAnArrivalAreaToo() {
        let line = line(.left(regionId: "arrival:b"), fix(at: AutoTestPlaces.atB, age: 30))

        #expect(line == "iOS: left Station B (phone 0 m away, ±12 m, 30 s old)")
    }

    @Test func givesNoDistanceForAnAreaThatIsNotAStation() {
        let fresh = fix(at: AutoTestPlaces.fiftyMetersFromA, age: 4)

        #expect(line(.left(regionId: "refresh"), fresh) == "iOS: left area around you")
        #expect(line(.entered(regionId: "arrival:unknown"), nil) == "iOS: entered arrival:unknown")
    }

    @Test func givesTheFirstStateInsideANewAreaThePositionToo() {
        let label = WatchedRegion.wakeLabel(
            ofId: "arrival:b", phoneAt: fix(at: AutoTestPlaces.atB, age: 2), now: now, catalog: AutoTestPlaces.catalog
        )
        var firstStates = RegionFirstStates(expecting: ["arrival:b"])
        _ = firstStates.take(id: "arrival:b", label: label, state: .inside, problems: "")

        #expect(
            firstStates.summary == "iOS: first state of 1 new areas: inside Station B (phone 0 m away, ±12 m, 2 s old)"
        )
    }

    @Test func neverCountsAPositionFromTheFutureAsOld() {
        let line = line(.entered(regionId: "arrival:a"), fix(at: AutoTestPlaces.stationA.coordinate, age: -3))

        #expect(line == "iOS: entered Station A (phone 0 m away, ±12 m, 0 s old)")
    }
}
