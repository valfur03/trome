import XCTest

final class NextTrainsTests: XCTestCase {
    @MainActor
    func testUserCanPickAStationAndSeeItsNextTrains() {
        let app = XCUIApplication.withRealGPS()
        app.launch()
        allowLocationAccessIfAsked()

        pickStation("Abbesses", searching: "abbesses", in: app)
        let stationName = app.staticTexts["currentStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: 5))
        XCTAssertEqual(stationName.label, "Abbesses")
        expectNextTrainsOutcome(in: app)

        pickStation("Pigalle", searching: "pigalle", in: app)
        XCTAssertTrue(stationName.waitForExistence(timeout: 5))
        XCTAssertEqual(stationName.label, "Pigalle")
        expectNextTrainsOutcome(in: app)
    }

    @MainActor
    private func pickStation(_ name: String, searching query: String, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 10))
        let chooseStation = app.buttons["chooseStation"]
        (chooseStation.exists ? chooseStation : app.buttons["changeStation"]).tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(query)
        app.buttons["chooseStation-\(name)"].tap()
    }

    @MainActor
    private func expectNextTrainsOutcome(in app: XCUIApplication) {
        let keyIsSet = app.staticTexts["primKeyStatus"].label == "Train data key: set"
        guard keyIsSet else {
            XCTAssertTrue(app.staticTexts["missingKeyMessage"].waitForExistence(timeout: 5))
            return
        }
        let departureRow = app.descendants(matching: .any).matching(identifier: "departureRow").firstMatch
        let noLiveData = app.staticTexts["noLiveDataMessage"]
        let deadline = Date().addingTimeInterval(30)
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
