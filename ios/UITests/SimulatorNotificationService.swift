import UserNotifications
import XCTest

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
