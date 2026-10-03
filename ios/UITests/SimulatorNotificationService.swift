import UserNotifications
import XCTest

// After a cold boot, the notification service of the Simulator can stay silent for minutes: SpringBoard
// serves the notification settings only once the background task service of iOS (dasd) accepts its tasks,
// and at boot dasd first handles the tasks of all the other services. Until then, the app shows no
// notification question. So the tests ask for the settings once, and wait for the answer before they start.
enum SimulatorNotificationService {
    static let timeoutAfterBoot: TimeInterval = 240
    @MainActor private static var hasAnswered = false

    @MainActor
    static func waitUntilItAnswers() {
        guard !hasAnswered else { return }
        let answer = XCTestExpectation(description: "The notification service of the Simulator answers")
        UNUserNotificationCenter.current().getNotificationSettings { _ in
            answer.fulfill()
        }
        let result = XCTWaiter().wait(for: [answer], timeout: timeoutAfterBoot)
        XCTAssertEqual(
            result,
            .completed,
            "The notification service of the Simulator did not answer within \(Int(timeoutAfterBoot)) seconds"
        )
        hasAnswered = result == .completed
    }
}
