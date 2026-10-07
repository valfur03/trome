// Seam: a real notification comes while the app is in the background, a tap on it opens the app,
// and the rider then sees the real Live Activity of that station in the Notification Center.
// A long press shows its actions, and iOS runs the chosen action in the app without opening it.
// A rider who does not tap it and opens the app at the station gets the Live Activity, and the notification goes.
// Why not cheaper: unit tests fake the notifier, the tap and the action; only iOS delivers the notification,
// shows its actions, tells the tap from an action, opens the app (or not) from it, and draws the Live Activity.
// Only iOS brings the app from the background to the front, and sends no new position while the phone stands still.
// Not guarded: the wake of a closed app by region monitoring. The Simulator cannot watch regions
// (in the iOS 27 Simulator, `isMonitoringAvailable` is false), so `--keep-running-in-background`
// keeps the app awake. QA and the iPhone check the wake.
import CoreLocation
import XCTest

final class ArrivalNotificationTests: E2ETestCase {
    private static let abbesses = CLLocation(latitude: 48.88439, longitude: 2.33838)
    private static let chateauRouge = CLLocation(latitude: 48.887102, longitude: 2.349556)
    private static let julesJoffrin = CLLocation(latitude: 48.892453, longitude: 2.344614)
    private static let longerThanAHeldPositionIsTrusted: TimeInterval = 21
    private static let notificationTitleIdentifier = "NotificationTitle"

    @MainActor
    func testTappingTheArrivalNotificationOfTheAppInTheBackgroundShowsTheLiveActivity() {
        let app = makeApp()
        app.launchArguments.append("--keep-running-in-background")
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        moveThePhone(to: Self.abbesses)

        let notification = arrivalNotification(titled: "Abbesses")
        XCTAssertTrue(waitFor(notification))
        notification.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITestTimeout.element))
        XCTAssertTrue(waitFor(shownStation(in: app)))
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Abbesses")))
        closeNotificationCenter()
    }

    @MainActor
    func testChoosingNotForOneHourOnTheArrivalNotificationSnoozesWithoutOpeningTheApp() {
        let app = makeApp()
        app.launchArguments.append("--keep-running-in-background")
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        moveThePhone(to: Self.chateauRouge)

        let notification = arrivalNotification(titled: "Château Rouge")
        XCTAssertTrue(waitFor(notification))
        notification.press(forDuration: 1.5)
        let notForOneHour = springboard.buttons["Not for 1 h"]
        XCTAssertTrue(waitFor(notForOneHour), "The long press showed no 'Not for 1 h' action")
        XCTAssertTrue(springboard.buttons["Not today"].exists, "The long press showed no 'Not today' action")
        notForOneHour.tap()

        XCTAssertTrue(waitForNo(notForOneHour))
        XCTAssertTrue(waitForNo(notification), "The notification stayed after the action")
        XCTAssertEqual(app.state, .runningBackground, "The action opened the app")

        bringToFront(app)
        let snoozeState = app.descendants(matching: .any)["snoozeState"]
        XCTAssertTrue(waitFor(snoozeState))
        XCTAssertTrue(snoozeState.label.contains("Back on at"), snoozeState.label)

        tap(app.buttons["cancelSnooze"])
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
    }

    @MainActor
    func testOpeningTheAppAtTheStationOfAnArrivalThatWasOnlyNotifiedShowsTheLiveActivity() {
        let app = makeApp()
        app.launchArguments.append("--keep-running-in-background")
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        moveThePhone(to: Self.julesJoffrin)

        let notification = arrivalNotification(titled: "Jules Joffrin")
        XCTAssertTrue(waitFor(notification))
        let standsStill = XCTestExpectation(description: "the phone stands still at the station")
        _ = XCTWaiter.wait(for: [standsStill], timeout: Self.longerThanAHeldPositionIsTrusted)

        bringToFront(app)
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Jules Joffrin")))
        XCTAssertTrue(waitForNo(notification), "The arrival notification stayed after the Live Activity started")
        closeNotificationCenter()
    }

    @MainActor
    private func arrivalNotification(titled title: String) -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", Self.notificationTitleIdentifier, title))
            .firstMatch
    }
}
