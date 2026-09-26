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
        allowLocationAccessIfAsked()

        XCTAssertTrue(app.staticTexts["nearestStationName"].waitForExistence(timeout: timeout))
        pickStation("Champ de Mars Tour Eiffel", searching: "champ de mars", in: app)
        XCTAssertTrue(app.staticTexts["currentStationName"].waitForExistence(timeout: timeout))
        let startButton = app.buttons["startLiveActivity"]
        XCTAssertTrue(startButton.waitForExistence(timeout: timeout))
        saveScreenshot(named: "app-main-screen")

        startButton.tap()
        let stopButton = app.buttons["stopLiveActivity"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: timeout))

        XCUIDevice.shared.press(.home)
        openNotificationCenter()
        saveScreenshot(named: "live-activity-notification-center")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(stopButton.waitForExistence(timeout: timeout))
        stopButton.tap()
        XCTAssertTrue(startButton.waitForExistence(timeout: timeout))
    }

    @MainActor
    private func pickStation(_ name: String, searching query: String, in app: XCUIApplication) {
        app.buttons["chooseStation"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        searchField.tap()
        searchField.typeText(query)
        let station = app.buttons["chooseStation-\(name)"]
        XCTAssertTrue(station.waitForExistence(timeout: timeout))
        station.tap()
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
    private func allowLocationAccessIfAsked() {
        let allowButton = springboard.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }
}
