// Seam: the widget process draws our ContentState (the station, both directions of a line, a branch,
// the lines of a hub) on the real Live Activity, and iOS runs the intents of its buttons in the app
// ("Show the next lines", snooze), whose effect the rider sees on the Live Activity and in the app.
// Why not cheaper: unit tests check the ContentState and the intents' rules; only the widget process
// draws the views, and only iOS runs a button's intent in the app.
// Fake: `--fake-trains` replaces the PRIM train data (a daily quota, data that changes). The real path
// stays covered by the unit tests of the PRIM client (recorded answers) and by QA with LIVE=1.
import CoreLocation
import XCTest

final class SnoozeTests: E2ETestCase {
    private static let lamarckCaulaincourt = CLLocation(latitude: 48.88969, longitude: 2.338524)
    private static let gareDeLEst = CLLocation(latitude: 48.876242, longitude: 2.358023)

    @MainActor
    func testUserSnoozesTheLiveActivityFromTheLockScreenThenCancelsTheSnooze() {
        let app = makeApp()
        app.launchArguments.append("--fake-trains")
        launch(app)
        turnOnTheAutomaticMode(in: app)
        stopLiveActivityIfShowing(in: app)
        moveThePhone(to: Self.lamarckCaulaincourt)
        XCTAssertTrue(waitFor(app.buttons["stopLiveActivity"]))

        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Lamarck - Caulaincourt")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Mairie d'Aubervilliers")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Mairie d'Issy")))

        moveThePhone(to: Self.gareDeLEst)
        XCTAssertTrue(waitFor(liveActivityStation("Gare de l'Est")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Porte de Clignancourt")))
        XCTAssertFalse(liveActivityElement(containing: "Villejuif - Louis Aragon").exists)
        tap(liveActivity.buttons["Show the next lines"])
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Villejuif - Louis Aragon")))
        XCTAssertTrue(liveActivityElement(containing: "Mairie d'Ivry").exists)
        XCTAssertTrue(waitForNo(liveActivityElement(containing: "Porte de Clignancourt")))
        tap(liveActivity.buttons["Snooze for 30 minutes"])
        XCTAssertTrue(waitForNo(liveActivity))
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
}
