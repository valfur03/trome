import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    private var decisionLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text).reversed()
    }

    private func comeBack(to model: AutoLiveActivityModel) async {
        let rough = PositionFix(coordinate: Places.atB, accuracyMeters: 1_000, timestamp: clock.now - 600)
        gps.currentFixCoordinate = Places.fiftyMetersFromA
        await model.handleRegionEvent(.entered(regionId: "arrival:a"), lastKnownFix: rough)
    }

    @Test(arguments: [nil, 600.0])
    func notifiesAgainAfterAWakeForLeavingTheStopAreaWithNoUsablePosition(positionAge: TimeInterval?) async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)
        let old = positionAge.map {
            PositionFix(coordinate: Places.fourHundredMetersFromA, accuracyMeters: 10, timestamp: clock.now - $0)
        }

        await model.handleRegionEvent(.left(regionId: "stop:a"), lastKnownFix: old)
        await comeBack(to: model)

        #expect(notifier.notified == [Places.stationA, Places.stationA])
        #expect(decisionLines.contains("Left Station A: iOS says the phone left its 250 m area"))
    }

    @Test func notifiesAgainAfterAWakeForLeavingTheStopAreaWithARoughPosition() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)
        let rough = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 400, timestamp: clock.now)

        await model.handleRegionEvent(.left(regionId: "stop:a"), lastKnownFix: rough)
        await comeBack(to: model)

        #expect(notifier.notified == [Places.stationA, Places.stationA])
    }

    @Test func ignoresAPositionFromBeforeTheExitAsThePhoneLeaves() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)
        let beforeTheExit = PositionFix(
            coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: clock.now - 60
        )

        await model.handleRegionEvent(.left(regionId: "stop:a"), lastKnownFix: beforeTheExit)

        #expect(notifier.notified == [Places.stationA])
        #expect(decisionLines.suffix(2) == [
            "Left Station A: iOS says the phone left its 250 m area",
            "No decision: the last position is inside the area that the phone left"
        ])
    }

    @Test func keepsOneNotificationWhenThePhoneLeavesOnlyTheArrivalArea() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)
        let inside = PositionFix(coordinate: Places.twoHundredMetersFromA, accuracyMeters: 10, timestamp: clock.now)

        await model.handleRegionEvent(.left(regionId: "arrival:a"), lastKnownFix: inside)
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
    }

    @Test func notifiesOnceAtTheStationForAnArrivalThatWaitedBehindAPopupWhenIOSClosedTheApp() async {
        do {
            let covered = makeModel()
            covered.setAppPhase(.active)
            covered.setAppPhase(.inactive)
            gps.report(Places.fiftyMetersFromA)
            await waitUntil { decisionLines.contains("Waits at Station A: a system popup covers the app") }
        }

        let relaunched = makeModel()
        await wake(relaunched, at: Places.fiftyMetersFromA)
        await wake(relaunched, at: Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
        #expect(decisionLines.filter { $0 == "Notified: Station A" }.count == 1)
    }
}
