import XCTest

final class AutoLiveActivityTests: E2ETestCase {
    @MainActor
    func testLiveActivityStartsSwitchesAndStopsByItselfNearStations() {
        let app = makeApp()
        app.launch()
        allowLocationAccessIfAsked()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
        leaveEveryStation(in: app)

        useFakePosition(atStation: "Abbesses", in: app)
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(lockScreenStation.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Abbesses")
        XCTAssertFalse(app.staticTexts["liveActivityError"].exists)

        useFakePosition(atStation: "Pigalle", in: app)
        waitForLabel("On the lock screen: Pigalle", of: lockScreenStation)
        XCTAssertEqual(app.buttons.matching(identifier: "stopLiveActivity").count, 1)

        openTestingTools(in: app)
        app.buttons["farFromAnyStation"].tap()
        goBack(in: app)
        XCTAssertTrue(lockScreenStation.waitForNonExistence(timeout: UITestTimeout.element))
    }

    @MainActor
    private func leaveEveryStation(in app: XCUIApplication) {
        openTestingTools(in: app)
        app.buttons["farFromAnyStation"].tap()
        XCTAssertTrue(app.staticTexts["48.42000, 2.63000"].waitForExistence(timeout: UITestTimeout.element))
        goBack(in: app)
        let stopButton = app.buttons["stopLiveActivity"]
        if stopButton.waitForExistence(timeout: 3) {
            stopButton.tap()
        }
        XCTAssertTrue(stopButton.waitForNonExistence(timeout: UITestTimeout.element))
    }

    @MainActor
    private func useFakePosition(atStation name: String, in app: XCUIApplication) {
        openTestingTools(in: app)
        app.buttons["pickStation"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: UITestTimeout.element))
        searchField.tap()
        searchField.typeText(name)
        let stationButton = app.buttons["station-\(name)"]
        XCTAssertTrue(stationButton.waitForExistence(timeout: UITestTimeout.element))
        stationButton.tap()
        XCTAssertTrue(app.staticTexts["Fake: \(name)"].waitForExistence(timeout: UITestTimeout.element))
        goBack(in: app)
    }

    @MainActor
    private func openTestingTools(in app: XCUIApplication) {
        let testingTools = app.buttons["testingTools"]
        XCTAssertTrue(testingTools.waitForExistence(timeout: UITestTimeout.element))
        testingTools.tap()
    }

    @MainActor
    private func goBack(in app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement) {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: UITestTimeout.element), .completed)
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
