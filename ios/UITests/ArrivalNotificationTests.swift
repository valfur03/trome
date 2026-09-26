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
        XCUIDevice.shared.location = XCUILocation(location: Self.abbesses)

        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Next trains at Abbesses"))
            .firstMatch
        XCTAssertTrue(waitFor(notification))
        notification.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITestTimeout.element))
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(waitFor(lockScreenStation))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Abbesses")
        XCTAssertEqual(app.state, .runningForeground)

        tap(app.buttons["stopLiveActivity"])
        XCTAssertTrue(waitFor(app.buttons["showNearestStationLiveActivity"]))
    }
}
