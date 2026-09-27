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
}
