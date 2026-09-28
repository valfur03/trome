// Seam: the real location popups of iOS come in the right order, then the "Show the Live Activity now"
// button asks ActivityKit, and the rider sees the Live Activity of the nearest station in the
// Notification Center, then sees it go after "Stop showing on the lock screen".
// Why not cheaper: unit tests fake the permission and the ActivityKit client; only iOS shows its
// popups, gives the position, and starts and ends a real Live Activity.
import CoreLocation
import XCTest

final class LiveActivityTests: E2ETestCase {
    private static let nearEiffelTower = CLLocation(latitude: 48.8584, longitude: 2.2945)
    private static let nearestStation = "Champ de Mars Tour Eiffel"

    @MainActor
    func testUserAllowsLocationThenShowsTheLiveActivityOfTheNearestStationAndStopsIt() {
        let app = makeApp()
        moveThePhone(to: Self.nearEiffelTower)
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        answerPermissionPrompts(in: app)
        stopLiveActivityIfShowing(in: app)

        let showButton = app.buttons["showNearestStationLiveActivity"]
        tap(showButton)
        XCTAssertTrue(waitFor(app.buttons["stopLiveActivity"]))
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation(Self.nearestStation)))
        closeNotificationCenter()

        app.activate()
        tap(app.buttons["stopLiveActivity"])
        XCTAssertTrue(waitFor(showButton))
        openNotificationCenter(over: app, expectingALiveActivity: false)
        XCTAssertTrue(waitForNo(liveActivity))
        closeNotificationCenter()
    }
}
