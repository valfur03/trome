// Seam: the widget process draws our ContentState (the station, both directions of a line, a train at the
// platform, a branch, the lines of a hub, one line per page) on the real Live Activity, and iOS runs the
// intents of its buttons in the app (the header of a hub page that shows the next line, snooze), whose effect
// the rider sees on the Live Activity and in the app.
// Why not cheaper: unit tests check the ContentState and the intents' rules; only the widget process
// draws the views, and only iOS runs a button's intent in the app.
// Fake: `--fake-trains at-platform` replaces the PRIM train data (a daily quota, data that changes). The real
// path stays covered by the unit tests of the PRIM client (recorded answers) and by QA with LIVE=1.
import CoreLocation
import XCTest

final class SnoozeTests: E2ETestCase {
    private static let lamarckCaulaincourt = CLLocation(latitude: 48.88969, longitude: 2.338524)
    private static let gareDeLEst = CLLocation(latitude: 48.876242, longitude: 2.358023)

    @MainActor
    func testUserSnoozesTheLiveActivityFromTheLockScreenThenCancelsTheSnooze() {
        let app = makeApp()
        app.launchArguments += ["--fake-trains", "at-platform"]
        launch(app)
        turnOnTheAutomaticMode(in: app)
        stopLiveActivityIfShowing(in: app)
        moveThePhone(to: Self.lamarckCaulaincourt)
        XCTAssertTrue(waitFor(app.buttons["stopLiveActivity"]))

        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Lamarck - Caulaincourt")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Mairie d'Aubervilliers")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Mairie d'Issy")))
        XCTAssertTrue(liveActivityElement(containing: "At the platform").exists)

        moveThePhone(to: Self.gareDeLEst)
        XCTAssertTrue(waitFor(liveActivityStation("Gare de l'Est")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Porte de Clignancourt")))
        XCTAssertFalse(liveActivityElement(containing: "Bobigny - Pablo Picasso").exists)
        XCTAssertTrue(waitFor(liveActivityPager))
        XCTAssertTrue(liveActivityPager.label.contains("2 other lines"), liveActivityPager.label)
        XCTAssertGreaterThanOrEqual(liveActivityPager.frame.height, 44, "The tap area of the pager is too small")
        tapOnTheLiveActivity(liveActivityPager, pointsBelowItsTop: 3)
        XCTAssertTrue(
            waitFor(liveActivityElement(containing: "Bobigny - Pablo Picasso")),
            "The next lines did not show. The app is \(app.state == .runningForeground ? "open" : "not open"), "
                + "and the Live Activity \(liveActivity.exists ? "shows" : "does not show") in the Notification Center"
        )
        XCTAssertTrue(liveActivityElement(containing: "Place d'Italie").exists)
        XCTAssertTrue(waitForNo(liveActivityElement(containing: "Porte de Clignancourt")))
        tapOnTheLiveActivity(liveActivityPager, pointsBelowItsTop: 3)
        XCTAssertTrue(waitFor(liveActivityRow(of: "Mairie d'Ivry")), "The fork of line 7 has no row for each end")
        XCTAssertTrue(liveActivityRow(of: "Villejuif - Louis Aragon").exists)
        tapOnTheLiveActivity(liveActivity.buttons["Snooze for 30 minutes"])
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
    private func liveActivityRow(of end: String) -> XCUIElement {
        liveActivity.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(end), "))
            .firstMatch
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
