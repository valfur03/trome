// Seam: a real notification comes while the app is in the background, a tap on it opens the app,
// and the rider then sees the real Live Activity of that station in the Notification Center.
// A long press shows its actions, and iOS runs the chosen action in the app without opening it.
// Why not cheaper: unit tests fake the notifier, the tap and the action; only iOS delivers the notification,
// shows its actions, tells the tap from an action, opens the app (or not) from it, and draws the Live Activity.
// Not guarded: the wake of a closed app by region monitoring. The Simulator cannot watch regions
// (TASK-44), so `--keep-running-in-background` keeps the app awake. QA and the iPhone check the wake.
import CoreLocation
import XCTest

final class ArrivalNotificationTests: E2ETestCase {
    private static let abbesses = CLLocation(latitude: 48.88439, longitude: 2.33838)
    private static let chateauRouge = CLLocation(latitude: 48.887102, longitude: 2.349556)

    @MainActor
    func testTappingTheArrivalNotificationOfTheAppInTheBackgroundShowsTheLiveActivity() {
        let app = makeApp()
        app.launchArguments.append("--keep-running-in-background")
        launch(app)
        stopLiveActivityIfShowing(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        moveThePhone(to: Self.abbesses)

        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Next trains at Abbesses"))
            .firstMatch
        XCTAssertTrue(waitFor(notification))
        notification.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITestTimeout.element))
        XCTAssertTrue(waitFor(app.buttons["stopLiveActivity"]))
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Abbesses")))
        closeNotificationCenter()

        app.activate()
        tap(app.buttons["stopLiveActivity"])
        XCTAssertTrue(waitFor(app.buttons["showNearestStationLiveActivity"]))
    }

    @MainActor
    func testChoosingNotForOneHourOnTheArrivalNotificationSnoozesWithoutOpeningTheApp() {
        let app = makeApp()
        app.launchArguments.append("--keep-running-in-background")
        launch(app)
        stopLiveActivityIfShowing(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        moveThePhone(to: Self.chateauRouge)

        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Next trains at Château Rouge"))
            .firstMatch
        XCTAssertTrue(waitFor(notification))
        notification.press(forDuration: 1.5)
        let notForOneHour = springboard.buttons["Not for 1 h"]
        XCTAssertTrue(waitFor(notForOneHour), "The long press showed no 'Not for 1 h' action")
        XCTAssertTrue(springboard.buttons["Not today"].exists, "The long press showed no 'Not today' action")
        notForOneHour.tap()

        XCTAssertTrue(waitForNo(notForOneHour))
        XCTAssertTrue(waitForNo(notification), "The notification stayed after the action")
        XCTAssertEqual(app.state, .runningBackground, "The action opened the app")

        app.activate()
        let snoozeState = app.descendants(matching: .any)["snoozeState"]
        XCTAssertTrue(waitFor(snoozeState))
        XCTAssertTrue(snoozeState.label.contains("Back on at"), snoozeState.label)

        tap(app.buttons["cancelSnooze"])
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
    }
}
