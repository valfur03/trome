// Seam: the phone reaches a station while the app is in the background, and iOS shows no notification of the app:
// only iOS keeps the list of what an app delivered. The rider then opens the app at the station, and sees the real
// Live Activity of that station in the Notification Center.
// Why not cheaper: unit tests show that the code has no path to send a notification, and that it writes why nothing
// started; only iOS can show that nothing reached the rider, and only iOS brings the app from the background to the
// front, sends no new position while the phone stands still, and draws the Live Activity.
// Not guarded: the wake of a closed app by region monitoring. The Simulator cannot watch regions
// (in the iOS 27 Simulator, `isMonitoringAvailable` is false), so `--keep-running-in-background`
// keeps the app awake. QA and the iPhone check the wake. A build of the Simulator has no silent start, so this test
// sees the path of a start that does not come.
import CoreLocation
import XCTest

final class BackgroundArrivalTests: E2ETestCase {
    private static let julesJoffrin = CLLocation(latitude: 48.892453, longitude: 2.344614)
    private static let longerThanAHeldPositionIsTrusted: TimeInterval = 21

    @MainActor
    func testAnArrivalInTheBackgroundShowsNoNotificationAndOpeningTheAppThereShowsTheLiveActivity() {
        let app = makeApp()
        app.launchArguments.append("--keep-running-in-background")
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        moveThePhone(to: Self.julesJoffrin)
        let standsStill = XCTestExpectation(description: "the phone stands still at the station")
        _ = XCTWaiter.wait(for: [standsStill], timeout: Self.longerThanAHeldPositionIsTrusted)

        openNotificationCenter(over: springboard, expectingALiveActivity: false)
        XCTAssertFalse(notificationOfTheApp.exists, "A notification of the app came at the station")
        closeNotificationCenter()

        bringToFront(app)
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Jules Joffrin")))
        XCTAssertFalse(notificationOfTheApp.exists, "A notification of the app came with the Live Activity")
        closeNotificationCenter()
    }

    /// The arrival notification that earlier builds sent (its title is the station), or any notification of the
    /// app, alone or in a stack (iOS starts its label with the name of the app).
    @MainActor
    private var notificationOfTheApp: XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(
                format: "(identifier == %@ AND label == %@) OR (identifier == %@ AND label BEGINSWITH %@)",
                "NotificationTitle", "Jules Joffrin", "NotificationShortLookView", "TROME"
            ))
            .firstMatch
    }
}
