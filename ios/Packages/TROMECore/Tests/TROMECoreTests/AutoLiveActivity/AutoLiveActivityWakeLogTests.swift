import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    private var decisions: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text)
    }

    @Test func logsTheNotificationOfARegionWake() async {
        let model = makeModel()

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(decisions == ["Notified: Station A"])
        #expect(wakeLog.entries.contains { $0.kind == .regions })
    }

    @Test func logsWhyASecondWakeAtTheSameStationGivesNoNotification() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
        #expect(decisions.first?.hasPrefix("No notification at Station A: same arrival as before") == true)
    }

    @Test func logsAWakeWithAPositionTooOldToDecide() async {
        let model = makeModel()
        let old = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: clock.now - 600)

        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: old)

        #expect(decisions == ["No decision: the last position is 600 s old"])
    }

    @Test func logsAWakeWithAPositionTooRoughToTrust() async {
        let model = makeModel()
        let rough = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 400, timestamp: clock.now - 30)

        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: rough)

        #expect(decisions == ["No decision: position not trusted, ±400 m and 30 s old (needs ±100 m and 120 s)"])
        #expect(notifier.notified.isEmpty)
    }

    @Test func logsThatAFakePositionMakesTheAppIgnoreAWake() async {
        let model = makeModel()
        locationService.use(.fake(Places.stationB.fakePosition))

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(decisions == ["Ignored: a fake position is on"])
    }

    @Test func logsEachReasonOnceWhileTheAppFollowsThePosition() async {
        let model = makeModel()
        await activate(model)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.isShowing }
        await model.handle(Places.fiftyMetersFromA)
        await model.handle(Places.fiftyMetersFromA)
        await model.handle(Places.twoHundredMetersFromA)
        await model.handle(Places.fourHundredMetersFromA)

        #expect(decisions == [
            "Live Activity ended: 400 m from Station A",
            "No station within 150 m: nearest is Station A, 200 m",
            "No notification at Station A: its Live Activity shows",
            "Live Activity started: Station A"
        ])
    }

    @Test func logsWhenTheAppComesOnScreenAndLeavesItButNotAPopup() {
        let model = makeModel()

        model.setAppPhase(.active)
        model.setAppPhase(.inactive)
        model.setAppPhase(.active)
        model.setAppPhase(.background)

        let screenChanges = wakeLog.entries.filter { $0.kind == .launch }.map(\.text)
        #expect(screenChanges == ["App in the background", "App on screen"])
    }
}
