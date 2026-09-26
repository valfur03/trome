import XCTest

final class LiveActivityTests: E2ETestCase {
    @MainActor
    func testUserCanShowAndStopTheLiveActivityOfThePickedStation() {
        let app = XCUIApplication.withRealGPS()
        app.launch()
        allowLocationAccessIfAsked()
        pickStation("Abbesses", searching: "abbesses", in: app)

        let stopButton = app.buttons["stopLiveActivity"]
        if stopButton.waitForExistence(timeout: 3) {
            stopButton.tap()
        }
        let startButton = app.buttons["startLiveActivity"]
        XCTAssertTrue(startButton.waitForExistence(timeout: UITestTimeout.element))
        startButton.tap()

        XCTAssertTrue(stopButton.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertFalse(app.staticTexts["liveActivityError"].exists)

        stopButton.tap()
        XCTAssertTrue(startButton.waitForExistence(timeout: UITestTimeout.element))
    }

    @MainActor
    private func pickStation(_ name: String, searching query: String, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
        let chooseStation = app.buttons["chooseStation"]
        (chooseStation.exists ? chooseStation : app.buttons["changeStation"]).tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: UITestTimeout.element))
        searchField.tap()
        searchField.typeText(query)
        app.buttons["chooseStation-\(name)"].tap()
    }

    @MainActor
    private func allowLocationAccessIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }
}
