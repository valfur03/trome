import Foundation
import Testing
@testable import RATPCore

extension AutoLiveActivityModelTests {
    @Test func asksForNotificationsOnceLocationIsAllowed() async {
        permission.authorization = .notDetermined
        let model = makeModel()
        await activate(model)
        #expect(notifier.authorizationRequestCount == 0)

        permission.authorization = .authorized
        await activate(model)
        await activate(model)
        await waitUntil { notifier.authorizationRequestCount > 0 }

        #expect(notifier.authorizationRequestCount == 1)
    }

    @Test func asksForNotificationsOnlyOnceTheAlwaysLocationQuestionIsAnswered() async {
        permission.isAskingAlways = true
        let model = makeModel()
        await activate(model)
        await waitUntil { permission.isWaitingForAlwaysQuestion }
        #expect(notifier.authorizationRequestCount == 0)

        permission.answerAlwaysQuestion()
        await waitUntil { notifier.authorizationRequestCount > 0 }

        #expect(notifier.authorizationRequestCount == 1)
    }

    @Test func saysWhenTheNotificationQuestionIsAnswered() async {
        permission.isAskingAlways = true
        let model = makeModel()
        await activate(model)
        #expect(model.hasAskedNotificationQuestion == false)

        permission.answerAlwaysQuestion()
        await waitUntil { model.hasAskedNotificationQuestion }

        #expect(model.hasAskedNotificationQuestion)
    }

    @Test func startsTheTappedLiveActivityWhileTheNotificationQuestionIsOpen() async {
        permission.isAskingAlways = true
        let model = makeModel()
        await model.notificationTapped(stationId: "a")

        await activate(model)
        await waitUntil { permission.isWaitingForAlwaysQuestion }

        #expect(permission.isWaitingForAlwaysQuestion)
        #expect(model.shownStation == Places.stationA)
        #expect(client.isShowing)
    }

    @Test func notForOneHourOnTheNotificationSnoozesAsTheOneHourButtonDoes() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)
        #expect(notifier.notified == [Places.stationA])

        await model.notificationActionChosen(.notForOneHour)
        await waitUntil { notifier.withdrawCount > 0 }

        #expect(automaticMode.mode == .snoozed(until: clock.now.addingTimeInterval(60 * 60)))
        #expect(notifier.withdrawCount > 0)
        #expect(client.started.isEmpty)
        #expect(model.shownStation == nil)
    }

    @Test func notTodayOnTheNotificationSnoozesUntilMidnight() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)

        await model.notificationActionChosen(.notToday)

        let midnight = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock.now)
        )
        #expect(automaticMode.mode == midnight.map { .snoozed(until: $0) })
        #expect(client.started.isEmpty)
    }
}
