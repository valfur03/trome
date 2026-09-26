import XCTest

final class FakePositionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testTesterCanFakeThePositionAndGoBackToTheRealGPS() {
        let app = XCUIApplication.withRealGPS()
        app.launch()
        allowLocationAccessIfAsked()

        app.buttons["testingTools"].tap()

        app.buttons["pickStation"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: UITestTimeout.element))
        searchField.tap()
        searchField.typeText("Chatelet")
        app.buttons["station-Châtelet"].tap()
        XCTAssertTrue(app.staticTexts["Fake: Châtelet"].waitForExistence(timeout: UITestTimeout.element))
        XCTAssertTrue(app.staticTexts["48.85856, 2.34743"].waitForExistence(timeout: UITestTimeout.element))

        app.buttons["farFromAnyStation"].tap()
        XCTAssertTrue(app.staticTexts["48.42000, 2.63000"].waitForExistence(timeout: UITestTimeout.element))

        let coordinatesField = app.textFields["coordinatesField"]
        coordinatesField.tap()
        coordinatesField.typeText("48.8584, 2.2945")
        app.buttons["useCoordinates"].tap()
        XCTAssertTrue(app.staticTexts["Fake: 48.85840, 2.29450"].waitForExistence(timeout: UITestTimeout.element))

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["fakePositionBanner"].waitForExistence(timeout: UITestTimeout.element))
        let stationName = app.staticTexts["nearestStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(stationName.label, "Champ de Mars Tour Eiffel")

        app.buttons["testingTools"].tap()
        app.buttons["useRealGPS"].tap()
        XCTAssertTrue(app.staticTexts["Real GPS"].waitForExistence(timeout: UITestTimeout.element))
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
