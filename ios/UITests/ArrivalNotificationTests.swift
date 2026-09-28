// Seam: a real notification comes while the app is in the background, a tap on it opens the app,
// and the rider then sees the real Live Activity of that station in the Notification Center.
// Why not cheaper: unit tests fake the notifier and the tap; only iOS delivers the notification,
// opens the app from it, and draws the Live Activity.
// Not guarded: the wake of a closed app by region monitoring. The Simulator cannot watch regions
// (TASK-44), so `--keep-running-in-background` keeps the app awake. QA and the iPhone check the wake.
import CoreLocation
import XCTest

final class ArrivalNotificationTests: E2ETestCase {
    private static let abbesses = CLLocation(latitude: 48.88439, longitude: 2.33838)

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
}
