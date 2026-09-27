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
        await activate(model)

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
        await activate(model)
        await reportAndWaitForRegions(roughFix(at: Places.fiftyMetersFromA))

        await model.startByHand(Places.stationA)
        await reportAndWaitForRegions(.exact(Places.fourHundredMetersFromA))

        #expect(model.shownStation == Places.stationA)
        #expect(client.endCount == 0)
    }

    @Test func countsAnOldPrecisePositionAsNearAStationStartedByHand() async {
        let model = makeModel()
        await activate(model)
        let stillFix = PositionFix(coordinate: Places.twoHundredMetersFromA, accuracyMeters: 10, timestamp: clock.now)
        await reportAndWaitForRegions(stillFix)
        clock.advance(by: 60)

        await model.startByHand(Places.stationA)
        gps.report(.exact(Places.fourHundredMetersFromA))
        await waitUntil { client.endCount == 1 }

        #expect(client.endCount == 1)
        #expect(model.shownStation == nil)
    }

    @Test func trustsAFakePositionSetLongAgo() async {
        let model = makeModel()
        await activate(model)
        locationService.use(.fake(FakePosition(name: "Near A", coordinate: Places.twoHundredMetersFromA)))
        await waitUntil { locationService.position != nil }
        clock.advance(by: Date().timeIntervalSince(clock.now) + 60)

        await model.startByHand(Places.stationA)
        locationService.use(.fake(FakePosition(name: "Far from A", coordinate: Places.fourHundredMetersFromA)))
        await waitUntil { client.endCount == 1 }

        #expect(client.endCount == 1)
        #expect(model.shownStation == nil)
    }

    @Test func watchesTheStationsAroundARoughPositionFromRegionMonitoring() async {
        let model = makeModel()

        await model.handleRegionEvent(enteredRegionId: nil, lastKnownFix: roughFix(at: Places.fiftyMetersFromA))

        #expect(notifier.notified.isEmpty)
        #expect(watcher.watched.last?.map(\.id) == ["arrival:a", "arrival:b", "refresh"])
    }

    @Test func doesNotEndOnARoughPositionFromRegionMonitoring() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.handleRegionEvent(enteredRegionId: nil, lastKnownFix: roughFix(at: Places.fourHundredMetersFromA))

        #expect(client.endCount == 0)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func notifiesOnEnteringAnArrivalAreaWithARoughPosition() async {
        let model = makeModel()

        await model.handleRegionEvent(enteredRegionId: "arrival:a", lastKnownFix: roughFix(at: Places.atB))

        #expect(notifier.notified == [Places.stationA])
    }

    @Test func usesAPositionOfTheLastTwoMinutesFromRegionMonitoring() async {
        let model = makeModel()
        let fix = PositionFix(
            coordinate: Places.fiftyMetersFromA,
            accuracyMeters: 10,
            timestamp: clock.now.addingTimeInterval(-100)
        )

        await model.handleRegionEvent(enteredRegionId: nil, lastKnownFix: fix)

        #expect(notifier.notified == [Places.stationA])
    }
}
