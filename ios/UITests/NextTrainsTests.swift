import XCTest

final class NextTrainsTests: E2ETestCase {
    @MainActor
    func testUserCanPickAStationAndSeeItsNextTrains() {
        let app = makeApp()
        app.launch()
        allowLocationAccessIfAsked()

        pickStation("Abbesses", searching: "abbesses", in: app)
        let stationName = app.staticTexts["currentStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(stationName.label, "Abbesses")
        expectNextTrainsOutcome(in: app)

        pickStation("Pigalle", searching: "pigalle", in: app)
        XCTAssertTrue(stationName.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(stationName.label, "Pigalle")
        expectNextTrainsOutcome(in: app)
    }

    @MainActor
    private func pickStation(_ name: String, searching query: String, in app: XCUIApplication) {
        let chooseStation = app.buttons["chooseStation"]
        let changeStation = app.buttons["changeStation"]
        if !chooseStation.exists, !changeStation.exists {
            openNextTrainsScreen(in: app)
        }
        (chooseStation.exists ? chooseStation : changeStation).tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: UITestTimeout.element))
        searchField.tap()
        searchField.typeText(query)
        app.buttons["chooseStation-\(name)"].tap()
    }

    @MainActor
    private func openNextTrainsScreen(in app: XCUIApplication) {
        let testingTools = app.buttons["testingTools"]
        XCTAssertTrue(testingTools.waitForExistence(timeout: UITestTimeout.element))
        testingTools.tap()
        let nextTrains = app.buttons["nextTrains"]
        XCTAssertTrue(app.staticTexts["locationSource"].waitForExistence(timeout: UITestTimeout.element))
        app.swipeUp()
        XCTAssertTrue(nextTrains.waitForExistence(timeout: UITestTimeout.element))
        nextTrains.tap()
        XCTAssertTrue(
            app.buttons["chooseStation"].waitForExistence(timeout: UITestTimeout.element)
                || app.buttons["changeStation"].exists
        )
    }

    @MainActor
    private func expectNextTrainsOutcome(in app: XCUIApplication) {
        let keyIsSet = app.staticTexts["primKeyStatus"].label == "Train data key: set"
        guard keyIsSet else {
            XCTAssertTrue(app.staticTexts["missingKeyMessage"].waitForExistence(timeout: UITestTimeout.element))
            return
        }
        let departureRow = app.descendants(matching: .any).matching(identifier: "departureRow").firstMatch
        let noLiveData = app.staticTexts["noLiveDataMessage"]
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while Date() < deadline, !departureRow.exists, !noLiveData.exists {
            _ = departureRow.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(departureRow.exists || noLiveData.exists, "Neither next trains nor 'no live data' appeared")
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
