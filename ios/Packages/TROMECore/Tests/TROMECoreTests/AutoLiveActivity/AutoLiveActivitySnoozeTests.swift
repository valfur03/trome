import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    @Test func snoozeEndsTheLiveActivityAndWithdrawsTheNotification() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.snooze(for: .thirtyMinutes)
        await waitUntil { notifier.withdrawCount > 0 }

        #expect(client.isShowing == false)
        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
        #expect(notifier.withdrawCount > 0)
        #expect(automaticMode.mode == .snoozed(until: clock.now.addingTimeInterval(30 * 60)))
    }

    @Test func neitherNotifiesNorStartsWhileSnoozed() async {
        let model = makeModel()
        await model.snooze(for: .oneHour)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { locationService.position == Places.fiftyMetersFromA }
        await wake(model, at: Places.atB)
        await activate(model)
        gps.report(Places.fiftyMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified.isEmpty)
        #expect(client.started.isEmpty)
    }

    @Test func notifiesAgainOnceTheSnoozeEnds() async {
        let model = makeModel()
        await model.snooze(for: .thirtyMinutes)
        await wake(model, at: Places.fiftyMetersFromA)

        clock.advance(by: 30 * 60)
        await wake(model, at: Places.atB)

        #expect(notifier.notified == [Places.stationB])
    }

    @Test func neitherNotifiesNorStartsWhileOff() async {
        let model = makeModel()
        automaticMode.setOn(false)

        await wake(model, at: Places.fiftyMetersFromA)
        await activate(model)
        await wake(model, at: Places.atB)

        #expect(notifier.notified.isEmpty)
        #expect(client.started.isEmpty)
        await waitUntil { notifier.withdrawCount > 0 }
        #expect(notifier.withdrawCount > 0)
    }

    @Test(arguments: [false, true])
    func startsByHandWhileSnoozedOrOff(isOff: Bool) async {
        let model = makeModel()
        if isOff {
            automaticMode.setOn(false)
        } else {
            await model.snooze(for: .restOfToday)
        }

        await model.startByHand(Places.stationA)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
    }
}
