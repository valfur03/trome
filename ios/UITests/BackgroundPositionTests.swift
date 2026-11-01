// Seam: the positions that iOS gives reach the app in the background only while the app follows the position.
// A rider who opened the app once and left it, with no Live Activity, must cost no battery: the phone that rides
// through a station at the speed of a train gives the app no position, so the app does no work for it.
// The proof is what iOS shows: an app that still got the positions would notify the arrival at the station.
// On an iPhone, the wake for the area of the station notifies instead; the Simulator cannot watch areas, so here
// nothing may come (the arrival with the app closed is checked on an iPhone, see ArrivalNotificationTests).
// iOS never suspends an app that an XCUITest launched, so the state of the app cannot show the drain.
// The location is "Always", as for a rider whose closed app wakes at stations: with "While Using the App",
// iOS sends no position to an app in the background that keeps no background session.
// Why not cheaper: the unit tests see that the app ends its position stream
// (`AutoLiveActivityBackgroundPositionTests`), but only iOS says whether it still sends positions to the app.
import CoreLocation
import XCTest

final class BackgroundPositionTests: E2ETestCase {
    private static let belAir = CLLocationCoordinate2D(latitude: 48.841347, longitude: 2.400916)
    /// 36 km/h, a point each second, from 350 m before Bel-Air to 250 m after it: about 30 positions within the
    /// 150 m of the station, and 6 plans of the station areas for an app that follows the position.
    private static let metersEachSecond = 10.0
    private static let rideSeconds = 60
    private static let metersBeforeTheStation = 350.0
    private static let notificationTitleIdentifier = "NotificationTitle"

    @MainActor
    func testARideThroughAStationGivesTheAppInTheBackgroundNoPositionWithNoLiveActivity() {
        let app = makeApp()
        addTeardownBlock { @MainActor in self.resetLocationAuthorization(of: app) }
        launchWithLocationAlways(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)
        moveThePhone(to: Self.pointOfTheRide(after: 0))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        let notification = arrivalNotification(titled: "Bel-Air")
        for second in 1...Self.rideSeconds {
            moveThePhone(to: Self.pointOfTheRide(after: second))
            XCTAssertFalse(
                notification.waitForExistence(timeout: 1),
                "A position reached the app in the background after \(second) s of ride, with no Live Activity"
            )
        }

        openNotificationCenter(over: springboard, expectingALiveActivity: false)
        XCTAssertFalse(notification.exists, "A position reached the app in the background, with no Live Activity")
        XCTAssertFalse(liveActivity.exists, "A position started a Live Activity from the background")
        closeNotificationCenter()
    }

    private static func pointOfTheRide(after second: Int) -> CLLocation {
        let meters = Double(second) * metersEachSecond - metersBeforeTheStation
        return CLLocation(latitude: belAir.latitude + meters / 111_000, longitude: belAir.longitude)
    }

    @MainActor
    private func arrivalNotification(titled title: String) -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", Self.notificationTitleIdentifier, title))
            .firstMatch
    }
}
