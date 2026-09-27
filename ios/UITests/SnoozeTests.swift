import XCTest

final class SnoozeTests: E2ETestCase {
    @MainActor
    func testUserSnoozesTheLiveActivityFromTheLockScreenThenCancelsTheSnooze() {
        let app = makeApp()
        app.launchArguments.append("--fake-trains")
        launch(app)
        turnOnTheAutomaticMode(in: app)
        leaveEveryStation(in: app)
        useFakePosition(atStation: "Abbesses", in: app)
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(waitFor(lockScreenStation))

        XCUIDevice.shared.press(.home)
        openNotificationCenter()
        XCTAssertTrue(waitFor(springboard.staticTexts["Abbesses"]))
        XCTAssertTrue(waitFor(springboard.staticTexts["Mairie d'Aubervilliers"]))
        XCTAssertTrue(waitFor(springboard.staticTexts["Mairie d'Issy"]))
        closeNotificationCenter()

        app.activate()
        useFakePosition(atStation: "Gare de l'Est", in: app)
        waitForLabel("On the lock screen: Gare de l'Est", of: lockScreenStation)
        XCUIDevice.shared.press(.home)
        openNotificationCenter(answeringTheLiveActivitiesPrompt: false)
        XCTAssertTrue(waitFor(springboard.staticTexts["Gare de l'Est"]))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Porte de Clignancourt")))
        XCTAssertFalse(liveActivityElement(containing: "Villejuif - Louis Aragon").exists)
        tap(springboard.buttons["Show the next lines"])
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Villejuif - Louis Aragon")))
        XCTAssertTrue(liveActivityElement(containing: "Mairie d'Ivry").exists)
        XCTAssertTrue(waitForNo(liveActivityElement(containing: "Porte de Clignancourt")))
        tap(springboard.buttons["Snooze for 30 minutes"])
        XCTAssertTrue(waitForNo(springboard.buttons["Snooze for 30 minutes"]))
        closeNotificationCenter()

        app.activate()
        XCTAssertTrue(waitFor(app.buttons["showNearestStationLiveActivity"]))
        let snoozeState = app.descendants(matching: .any)["snoozeState"]
        XCTAssertTrue(waitFor(snoozeState))
        XCTAssertTrue(snoozeState.label.contains("Snoozed"))
        XCTAssertTrue(snoozeState.label.contains("Back on at"))

        tap(app.buttons["cancelSnooze"])
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
        XCTAssertFalse(snoozeState.exists)
        leaveEveryStation(in: app)
    }

    @MainActor
    func testUserTurnsOffTheAutomaticModeAndStillShowsTheLiveActivityByHand() {
        let app = makeApp()
        launch(app)
        turnOnTheAutomaticMode(in: app)
        leaveEveryStation(in: app)

        let toggle = app.switches["automaticModeToggle"]
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitForValue("0", of: toggle))
        XCTAssertFalse(app.buttons["snoozeMenu"].exists)
        useFakePosition(atStation: "Abbesses", in: app)
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertFalse(lockScreenStation.waitForExistence(timeout: 5))

        tap(app.buttons["showNearestStationLiveActivity"])
        XCTAssertTrue(waitFor(lockScreenStation))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Abbesses")

        tap(app.buttons["stopLiveActivity"])
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitForValue("1", of: toggle))
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
        leaveEveryStation(in: app)
    }

    @MainActor
    private func turnOnTheAutomaticMode(in app: XCUIApplication) {
        let cancelSnooze = app.buttons["cancelSnooze"]
        let toggle = app.switches["automaticModeToggle"]
        XCTAssertTrue(waitFor(toggle))
        if cancelSnooze.exists {
            cancelSnooze.tap()
        }
        if toggle.value as? String == "0" {
            toggle.switches.firstMatch.tap()
        }
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
    }

    @MainActor
    private func openNotificationCenter(answeringTheLiveActivitiesPrompt: Bool = true) {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: middle)
        guard answeringTheLiveActivitiesPrompt else { return }
        let allowLiveActivities = springboard.buttons["Allow"]
        if allowLiveActivities.waitForExistence(timeout: 5) {
            allowLiveActivities.tap()
        }
    }

    @MainActor
    private func liveActivityElement(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func closeNotificationCenter() {
        XCUIDevice.shared.press(.home)
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: UITestTimeout.element) == .completed
    }
}
