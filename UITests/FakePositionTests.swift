import XCTest

final class FakePositionTests: XCTestCase {
    @MainActor
    func testTesterCanFakeThePositionAndGoBackToTheRealGPS() {
        let app = XCUIApplication()
        app.launch()
        allowLocationAccessIfAsked()

        app.buttons["testingTools"].tap()

        app.buttons["pickStation"].tap()
        app.buttons["station-Châtelet"].tap()
        XCTAssertTrue(app.staticTexts["Fake: Châtelet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["48.85855, 2.34743"].waitForExistence(timeout: 5))

        app.buttons["farFromAnyStation"].tap()
        XCTAssertTrue(app.staticTexts["48.42000, 2.63000"].waitForExistence(timeout: 5))

        let coordinatesField = app.textFields["coordinatesField"]
        coordinatesField.tap()
        coordinatesField.typeText("48.8584, 2.2945")
        app.buttons["useCoordinates"].tap()
        XCTAssertTrue(app.staticTexts["Fake: 48.85840, 2.29450"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["fakePositionBanner"].waitForExistence(timeout: 5))
        let stationName = app.staticTexts["nearestStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: 5))
        XCTAssertEqual(stationName.label, "Champ de Mars Tour Eiffel")

        app.buttons["testingTools"].tap()
        app.buttons["useRealGPS"].tap()
        XCTAssertTrue(app.staticTexts["Real GPS"].waitForExistence(timeout: 5))
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
