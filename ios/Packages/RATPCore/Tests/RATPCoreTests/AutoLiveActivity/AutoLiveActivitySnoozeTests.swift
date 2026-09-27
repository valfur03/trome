import Foundation
import Testing
@testable import RATPCore

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
        await model.handleMonitoredPosition(Places.atB)
        await model.setAppActive(true)
        gps.report(Places.fiftyMetersFromA)
        await model.handleMonitoredPosition(Places.fiftyMetersFromA)

        #expect(notifier.notified.isEmpty)
        #expect(client.started.isEmpty)
    }

    @Test func notifiesAgainOnceTheSnoozeEnds() async {
        let model = makeModel()
        await model.snooze(for: .thirtyMinutes)
        await model.handleMonitoredPosition(Places.fiftyMetersFromA)

        clock.advance(by: 30 * 60)
        await model.handleMonitoredPosition(Places.atB)

        #expect(notifier.notified == [Places.stationB])
    }

    @Test func neitherNotifiesNorStartsWhileOff() async {
        let model = makeModel()
        automaticMode.setOn(false)

        await model.handleMonitoredPosition(Places.fiftyMetersFromA)
        await model.setAppActive(true)
        await model.handleMonitoredPosition(Places.atB)

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
