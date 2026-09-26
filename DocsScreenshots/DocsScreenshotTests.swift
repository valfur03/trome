import XCTest

final class DocsScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 30

    @MainActor
    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testTakeTheScreenshotsOfTheDocs() {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-location-source")
        app.launch()

        let stopButton = app.buttons["stopLiveActivity"]
        let showButton = app.buttons["showNearestStationLiveActivity"]
        let location = app.descendants(matching: .any)["locationPermissionStatus"]
        let notifications = app.descendants(matching: .any)["notificationsPermissionStatus"]
        answerPermissionQuestions {
            location.exists && location.label == "Location, Always"
                && notifications.exists && notifications.label == "Notifications, On"
        }
        XCTAssertTrue(showButton.waitForExistence(timeout: timeout))
        saveScreenshot(named: "app-main-screen")

        showButton.tap()
        XCTAssertTrue(stopButton.waitForExistence(timeout: timeout))

        XCUIDevice.shared.press(.home)
        openNotificationCenter()
        saveScreenshot(named: "live-activity-notification-center")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(stopButton.waitForExistence(timeout: timeout))
        stopButton.tap()
        XCTAssertTrue(showButton.waitForExistence(timeout: timeout))
    }

    @MainActor
    private func openNotificationCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: middle)
        let allowLiveActivities = springboard.buttons["Allow"]
        if allowLiveActivities.waitForExistence(timeout: 5) {
            allowLiveActivities.tap()
        }
        sleep(2)
    }

    @MainActor
    private func saveScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func answerPermissionQuestions(until isSettled: () -> Bool) {
        let answers = ["Allow While Using App", "Change to Always Allow", "Allow"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !isSettled() {
            for answer in answers where springboard.buttons[answer].exists {
                springboard.buttons[answer].tap()
            }
            sleep(1)
        }
        XCTAssertTrue(isSettled(), "The location and notification permissions did not settle")
    }
}
