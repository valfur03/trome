import XCTest

final class FakePositionTests: E2ETestCase {
    @MainActor
    func testTesterCanFakeThePositionAndGoBackToTheRealGPS() {
        let app = makeApp()
        launch(app)

        app.buttons["testingTools"].tap()

        let coordinatesField = app.textFields["coordinatesField"]
        coordinatesField.tap()
        coordinatesField.typeText("48.8584, 2.2945")
        app.buttons["useCoordinates"].tap()
        XCTAssertTrue(app.staticTexts["Fake: 48.85840, 2.29450"].waitForExistence(timeout: UITestTimeout.element))
        let stationName = app.staticTexts["nearestStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(stationName.label, "Champ de Mars Tour Eiffel")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["fakePositionBanner"].waitForExistence(timeout: UITestTimeout.element))

        app.buttons["testingTools"].tap()
        app.buttons["useRealGPS"].tap()
        XCTAssertTrue(app.staticTexts["Real GPS"].waitForExistence(timeout: UITestTimeout.element))
    }
}
