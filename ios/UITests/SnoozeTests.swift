// Seam: the widget process draws our ContentState (the station, both directions of a line, a train at the
// platform, a branch, one row for each end of a fork, the lines of a hub, one line per page) on the real Live
// Activity, and iOS runs the intents of its buttons in the app (the header of a hub page that shows the next
// line, snooze), whose effect the rider sees on the Live Activity and in the app. The widget draws the page that
// the rider tapped to from a content that shows the first page, as each push of the server does, through the app
// group that the app and the widget share.
// Why not cheaper: unit tests check the ContentState and the intents' rules; only the widget process
// draws the views, and only iOS runs a button's intent in the app.
// Fake: `--fake-trains at-platform` replaces the PRIM train data (a daily quota, data that changes). The real
// path stays covered by the unit tests of the PRIM client (recorded answers) and by QA with LIVE=1.
// `--content-as-the-server` makes the app send each content as the server pushes it (the first page shown, every page
// carried), since a push of Apple cannot reach the Simulator; the contract tests of the app and the server prove that
// the two contents are the same, and the real push is checked on an iPhone.
import CoreLocation
import XCTest

final class SnoozeTests: E2ETestCase {
    private static let lamarckCaulaincourt = CLLocation(latitude: 48.88969, longitude: 2.338524)
    private static let gareDeLEst = CLLocation(latitude: 48.876242, longitude: 2.358023)
    private static let bastille = CLLocation(latitude: 48.852919, longitude: 2.369048)

    @MainActor
    func testUserSnoozesTheLiveActivityFromTheLockScreenThenCancelsTheSnooze() {
        let app = makeApp()
        app.launchArguments += ["--fake-trains", "at-platform"]
        launch(app)
        turnOnTheAutomaticMode(in: app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)
        moveThePhone(to: Self.lamarckCaulaincourt)
        XCTAssertTrue(waitFor(shownStation(in: app)))

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
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Bobigny - Pablo Picasso")), nextLinesDidNotShow(in: app))
        XCTAssertTrue(liveActivityElement(containing: "Place d'Italie").exists)
        XCTAssertTrue(waitForNo(liveActivityElement(containing: "Porte de Clignancourt")))
        tapOnTheLiveActivity(liveActivityPager, pointsBelowItsTop: 3)
        XCTAssertTrue(waitFor(liveActivityElement(containing: "La Courneuve")), nextLinesDidNotShow(in: app))
        XCTAssertTrue(waitFor(liveActivityRow(of: "Mairie d'Ivry")), "The fork of line 7 has no row for each end")
        XCTAssertTrue(liveActivityRow(of: "Villejuif - Louis Aragon").exists)
        tapOnTheLiveActivity(liveActivity.buttons["Snooze for 30 minutes"])
        XCTAssertTrue(waitForNo(liveActivity))
        closeNotificationCenter()

        bringToFront(app)
        XCTAssertTrue(waitForNo(shownStation(in: app)))
        let snoozeState = app.descendants(matching: .any)["snoozeState"]
        XCTAssertTrue(waitFor(snoozeState))
        XCTAssertTrue(snoozeState.label.contains("Snoozed"))
        XCTAssertTrue(snoozeState.label.contains("Back on at"))

        tap(app.buttons["cancelSnooze"])
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
        XCTAssertFalse(snoozeState.exists)
    }

    /// A rider taps to the page of line 5, and the updates of the server, which show line 1, keep it.
    @MainActor
    func testTheTappedPageHoldsWhenTheContentShowsTheFirstPage() {
        let app = makeApp()
        app.launchArguments += ["--fake-trains", "--content-as-the-server"]
        launch(app)
        turnOnTheAutomaticMode(in: app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)
        moveThePhone(to: Self.bastille)
        XCTAssertTrue(waitFor(shownStation(in: app)))

        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Bastille")))
        XCTAssertTrue(waitFor(liveActivityElement(containing: "La Défense")))
        tapOnTheLiveActivity(liveActivityPager, pointsBelowItsTop: 3)
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Bobigny - Pablo Picasso")), nextLinesDidNotShow(in: app))
        XCTAssertTrue(waitForNo(liveActivityElement(containing: "La Défense")))
        tapOnTheLiveActivity(liveActivityPager, pointsBelowItsTop: 3)
        XCTAssertTrue(waitFor(liveActivityElement(containing: "Balard")), nextLinesDidNotShow(in: app))
        closeNotificationCenter()
    }

    @MainActor
    private func nextLinesDidNotShow(in app: XCUIApplication) -> String {
        "The next lines did not show. The app is \(app.state == .runningForeground ? "open" : "not open"), "
            + "and the Live Activity \(liveActivity.exists ? "shows" : "does not show") in the Notification Center. "
            + "The app log says 'show the next lines' when the tap reached the app, "
            + "and the context of the kept run names a tap that iOS dropped"
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
