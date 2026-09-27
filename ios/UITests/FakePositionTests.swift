import XCTest

final class FakePositionTests: E2ETestCase {
    @MainActor
    func testTesterCanFakeThePositionAndGoBackToTheRealGPS() {
        let app = makeApp()
        launch(app)

        tap(app.buttons["testingTools"])

        let coordinatesField = app.textFields["coordinatesField"]
        tap(coordinatesField)
        coordinatesField.typeText("48.8584, 2.2945")
        tap(app.buttons["useCoordinates"])
        XCTAssertTrue(waitFor(app.staticTexts["Fake: 48.85840, 2.29450"]))
        let stationName = app.staticTexts["nearestStationName"]
        XCTAssertTrue(waitFor(stationName))
        XCTAssertEqual(stationName.label, "Champ de Mars Tour Eiffel")

        goBack(in: app)
        let banner = app.staticTexts["fakePositionBanner"]
        for _ in 0..<3 where !banner.exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(waitFor(banner))

        tap(app.buttons["testingTools"])
        tap(app.buttons["useRealGPS"])
        XCTAssertTrue(waitFor(app.staticTexts["Real GPS"]))
    }
}
