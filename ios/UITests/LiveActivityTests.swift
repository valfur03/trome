// Seam: the real location popups of iOS come in the right order, then the position that iOS gives near a station,
// with the app open, makes the app ask ActivityKit for a Live Activity, and the rider sees it in the Notification
// Center, then sees it go after "Snooze" in the app.
// Why not cheaper: unit tests fake the permission, the position and the ActivityKit client; only iOS shows its
// popups, gives the position, and starts and ends a real Live Activity.
import CoreLocation
import XCTest

final class LiveActivityTests: E2ETestCase {
    private static let atChampDeMars = CLLocation(latitude: 48.8565, longitude: 2.2897)
    private static let station = "Champ de Mars Tour Eiffel"

    @MainActor
    func testUserAllowsLocationAtAStationThenSeesTheLiveActivityAndSnoozesIt() {
        let app = makeApp()
        moveThePhone(to: Self.atChampDeMars)
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        answerPermissionPrompts(in: app)

        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation(Self.station)))
        closeNotificationCenter()

        bringToFront(app)
        tap(app.buttons["snoozeMenu"])
        tap(app.buttons["snooze-thirtyMinutes"])
        openNotificationCenter(over: app, expectingALiveActivity: false)
        XCTAssertTrue(waitForNo(liveActivity))
        closeNotificationCenter()

        bringToFront(app)
        moveThePhone(to: Self.farFromAnyStation)
        tap(app.buttons["cancelSnooze"])
        XCTAssertTrue(waitFor(app.buttons["snoozeMenu"]))
    }
}
