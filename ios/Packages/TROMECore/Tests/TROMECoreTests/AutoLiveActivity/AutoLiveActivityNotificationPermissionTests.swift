import Foundation
import Testing
@testable import TROMECore

// The notification question stays, in its place after the location questions, though the app sends no
// notification of its own.
extension AutoLiveActivityModelTests {
    @Test func asksForNotificationsOnceLocationIsAllowed() async {
        permission.authorization = .notDetermined
        let model = makeModel()
        await activate(model)
        #expect(notifications.authorizationRequestCount == 0)

        permission.authorization = .authorized
        await activate(model)
        await activate(model)
        await waitUntil { notifications.authorizationRequestCount > 0 }

        #expect(notifications.authorizationRequestCount == 1)
    }

    @Test func asksForNotificationsOnlyOnceTheAlwaysLocationQuestionIsAnswered() async {
        permission.isAskingAlways = true
        let model = makeModel()
        await activate(model)
        await waitUntil { permission.isWaitingForAlwaysQuestion }
        #expect(notifications.authorizationRequestCount == 0)

        permission.answerAlwaysQuestion()
        await waitUntil { notifications.authorizationRequestCount > 0 }

        #expect(notifications.authorizationRequestCount == 1)
    }

    // After Allow Once, the location questions end when the rider leaves the app: the notifications question comes
    // at the next return, never out of the app.
    @Test func asksForNotificationsAtTheNextReturnWhenTheRiderLeftDuringTheLocationQuestions() async {
        permission.isAskingAlways = true
        let model = makeModel()
        await activate(model)
        await waitUntil { permission.isWaitingForAlwaysQuestion }

        model.setAppPhase(.background)
        permission.answerAlwaysQuestion()
        await waitUntil { !model.hasAskedForNotifications }
        #expect(notifications.authorizationRequestCount == 0)

        await activate(model)
        await waitUntil { notifications.authorizationRequestCount > 0 }

        #expect(notifications.authorizationRequestCount == 1)
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
}
