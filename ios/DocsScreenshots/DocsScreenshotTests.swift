import XCTest

final class DocsScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 30

    @MainActor
    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override static func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            SimulatorNotificationService.waitUntilItAnswers()
        }
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

        app.buttons["testingTools"].tap()
        XCTAssertTrue(app.buttons["useRealGPS"].waitForExistence(timeout: timeout))
        saveScreenshot(named: "app-testing-tools")
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
        let answers: [(button: String, screenshot: String?)] = [
            (button: "Allow While Using App", screenshot: "app-location-permission"),
            (button: "Change to Always Allow", screenshot: "app-always-permission"),
            (button: "Allow", screenshot: "app-notification-permission")
        ]
        var savedScreenshots: Set<String> = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !isSettled() {
            for answer in answers where springboard.buttons[answer.button].exists {
                if let screenshot = answer.screenshot, !savedScreenshots.contains(screenshot) {
                    sleep(1)
                    saveScreenshot(named: screenshot)
                    savedScreenshots.insert(screenshot)
                }
                springboard.buttons[answer.button].tap()
            }
            sleep(1)
        }
        XCTAssertTrue(isSettled(), "The location and notification permissions did not settle")
        XCTAssertEqual(
            savedScreenshots,
            ["app-location-permission", "app-always-permission", "app-notification-permission"],
            "The location, Always and notification questions were not all on screen"
        )
    }
}
