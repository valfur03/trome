import XCTest

final class AutoLiveActivityTests: E2ETestCase {
    @MainActor
    func testLiveActivityStartsSwitchesAndStopsByItselfNearStations() {
        let app = makeApp()
        launch(app)
        leaveEveryStation(in: app)

        useFakePosition(atStation: "Abbesses", in: app)
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(waitFor(lockScreenStation))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Abbesses")
        XCTAssertFalse(app.staticTexts["liveActivityError"].exists)

        useFakePosition(atStation: "Pigalle", in: app)
        waitForLabel("On the lock screen: Pigalle", of: lockScreenStation)
        XCTAssertEqual(app.buttons.matching(identifier: "stopLiveActivity").count, 1)

        tap(app.buttons["testingTools"])
        tap(app.buttons["farFromAnyStation"])
        goBack(in: app)
        XCTAssertTrue(waitForNo(lockScreenStation))
    }

    @MainActor
    private func leaveEveryStation(in app: XCUIApplication) {
        tap(app.buttons["testingTools"])
        tap(app.buttons["farFromAnyStation"])
        XCTAssertTrue(waitFor(app.staticTexts["48.42000, 2.63000"]))
        goBack(in: app)
        stopLiveActivityIfShowing(in: app)
    }

    @MainActor
    private func useFakePosition(atStation name: String, in app: XCUIApplication) {
        tap(app.buttons["testingTools"])
        tap(app.buttons["pickStation"])
        let searchField = app.searchFields.firstMatch
        tap(searchField)
        searchField.typeText(name)
        tap(app.buttons["station-\(name)"])
        XCTAssertTrue(waitFor(app.staticTexts["Fake: \(name)"]))
        goBack(in: app)
    }

    @MainActor
    private func goBack(in app: XCUIApplication) {
        tap(app.navigationBars.buttons.firstMatch)
        XCTAssertTrue(waitFor(app.staticTexts["appTitle"]))
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement) {
        guard element.label != label else { return }
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: UITestTimeout.element), .completed)
    }
}
