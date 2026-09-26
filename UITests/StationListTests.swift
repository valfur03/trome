import XCTest

final class StationListTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testTesterCanSearchTheStationList() {
        let app = XCUIApplication()
        app.launch()
        allowLocationAccessIfAsked()

        app.buttons["testingTools"].tap()
        app.swipeUp()
        app.buttons["allStations"].tap()
        let stationCount = app.staticTexts["stationCount"]
        XCTAssertTrue(stationCount.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertGreaterThan(Int(stationCount.label.prefix { $0.isNumber }) ?? 0, 500)

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("chatelet")

        XCTAssertTrue(app.staticTexts["2 stations"].waitForExistence(timeout: UITestTimeout.element))
        let rows = app.descendants(matching: .any).matching(identifier: "stationRow")
        XCTAssertTrue(rows.element(boundBy: 0).label.hasPrefix("Châtelet, Metro 1"))
        XCTAssertTrue(rows.element(boundBy: 1).label.hasPrefix("Châtelet - Les Halles, RER A"))
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
