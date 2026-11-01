// Seam: the position that iOS gives (set with XCUIDevice.location, read by our Core Location code)
// reaches the rules, and ActivityKit really starts, switches and ends the Live Activity that the
// rider sees in the Notification Center. The switch and the end happen as in a pocket: the location
// "Always", the app sent to the background, and there long enough for iOS to stop the position stream
// of an app that is no longer in use (about 10 s, in the log of locationd), so the keeper's positions decide.
// No launch argument of the tests keeps the app awake or following the position.
// Why not cheaper: unit tests check the rules with a fake position provider and a fake ActivityKit
// client; only the Simulator shows that iOS still sends positions and that the real Live Activity follows them.
import CoreLocation
import XCTest

final class AutoLiveActivityTests: E2ETestCase {
    private static let pigalle = CLLocation(latitude: 48.882213, longitude: 2.337713)
    private static let anvers = CLLocation(latitude: 48.882869, longitude: 2.344155)
    /// iOS stops the stream about 10 s after the app leaves the screen; the rest is a margin for a busy Mac.
    private static let longerThanIOSKeepsTheStreamOffScreen: TimeInterval = 20

    @MainActor
    func testLiveActivityStartsSwitchesAndStopsByItselfNearStationsInThePocket() {
        let app = makeApp()
        addTeardownBlock { @MainActor in self.resetLocationAuthorization(of: app) }
        launchWithLocationAlways(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)

        moveThePhone(to: Self.pigalle)
        XCTAssertTrue(waitFor(shownStation(in: app)))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        openNotificationCenter(over: springboard)
        XCTAssertTrue(waitFor(liveActivityStation("Pigalle")))
        let inThePocket = XCTestExpectation(description: "the phone stays in the pocket")
        _ = XCTWaiter.wait(for: [inThePocket], timeout: Self.longerThanIOSKeepsTheStreamOffScreen)

        moveThePhone(to: Self.anvers)
        XCTAssertTrue(waitFor(liveActivityStation("Anvers")), "The Live Activity did not switch in the pocket")
        XCTAssertFalse(liveActivityStation("Pigalle").exists)

        moveThePhone(to: Self.farFromAnyStation)
        XCTAssertTrue(waitForNo(liveActivity), "The Live Activity did not end in the pocket")
        closeNotificationCenter()
    }
}
