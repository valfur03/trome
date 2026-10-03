// Seam: the position that iOS gives (set with XCUIDevice.location, read by our Core Location code)
// reaches the rules, and ActivityKit really starts, switches and ends the Live Activity that the
// rider sees in the Notification Center. The switch and the end happen with the app in the background,
// as in a pocket: the app keeps getting positions only while its Live Activity shows.
// Why not cheaper: unit tests check the rules with a fake position provider and a fake ActivityKit
// client; only the Simulator shows that the real position and the real Live Activity follow them.
import CoreLocation
import XCTest

final class AutoLiveActivityTests: E2ETestCase {
    private static let pigalle = CLLocation(latitude: 48.882213, longitude: 2.337713)
    private static let anvers = CLLocation(latitude: 48.882869, longitude: 2.344155)

    @MainActor
    func testLiveActivityStartsSwitchesAndStopsByItselfNearStations() {
        let app = makeApp()
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)

        moveThePhone(to: Self.pigalle)
        XCTAssertTrue(waitFor(shownStation(in: app)))
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Pigalle")))

        moveThePhone(to: Self.anvers)
        XCTAssertTrue(waitFor(liveActivityStation("Anvers")))
        XCTAssertFalse(liveActivityStation("Pigalle").exists)

        moveThePhone(to: Self.farFromAnyStation)
        XCTAssertTrue(waitForNo(liveActivity))
        closeNotificationCenter()
    }
}
