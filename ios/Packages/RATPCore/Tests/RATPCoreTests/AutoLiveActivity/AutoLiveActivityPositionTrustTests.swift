import Foundation
import Testing
@testable import RATPCore

extension AutoLiveActivityModelTests {
    private func roughFix(at coordinate: Coordinate) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: 500, timestamp: clock.now)
    }

    private func oldFix(at coordinate: Coordinate) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: 10, timestamp: clock.now.addingTimeInterval(-60))
    }

    private func reportAndWaitForRegions(_ fix: PositionFix) async {
        let count = watcher.watched.count
        gps.report(fix)
        await waitUntil { watcher.watched.count > count }
    }

    @Test func doesNotStartOnARoughPosition() async {
        let model = makeModel()
        await model.setAppActive(true)

        await reportAndWaitForRegions(roughFix(at: Places.fiftyMetersFromA))

        #expect(client.started.isEmpty)
        #expect(notifier.notified.isEmpty)
        #expect(watcher.watched.last?.map(\.id) == ["arrival:a", "arrival:b", "refresh"])
    }

    @Test func doesNotSwitchOnARoughPosition() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await reportAndWaitForRegions(roughFix(at: Places.atB))

        #expect(model.shownStation == Places.stationA)
        #expect(client.updates.allSatisfy { $0.stationName == "Station A" })
    }

    @Test func doesNotEndOnARoughPosition() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await reportAndWaitForRegions(roughFix(at: Places.fourHundredMetersFromA))

        #expect(client.endCount == 0)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func doesNotEndOnAnOldPosition() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await reportAndWaitForRegions(oldFix(at: Places.fourHundredMetersFromA))

        #expect(client.endCount == 0)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func doesNotCountARoughPositionAsNearAStationStartedByHand() async {
        let model = makeModel()
        await model.setAppActive(true)
        await reportAndWaitForRegions(roughFix(at: Places.fiftyMetersFromA))

        await model.startByHand(Places.stationA)
        await reportAndWaitForRegions(.exact(Places.fourHundredMetersFromA))

        #expect(model.shownStation == Places.stationA)
        #expect(client.endCount == 0)
    }
}
