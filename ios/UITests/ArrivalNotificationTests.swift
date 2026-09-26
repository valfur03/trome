import CoreLocation
import XCTest

final class ArrivalNotificationTests: E2ETestCase {
    private static let abbesses = CLLocation(latitude: 48.88439, longitude: 2.33838)

    @MainActor
    func testTappingTheArrivalNotificationOfTheAppInTheBackgroundShowsTheLiveActivity() {
        let app = makeApp()
        launch(app)
        stopLiveActivityIfShowing(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        XCUIDevice.shared.location = XCUILocation(location: Self.abbesses)

        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Next trains at Abbesses"))
            .firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: UITestTimeout.element))
        notification.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITestTimeout.element))
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(lockScreenStation.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Abbesses")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func stopLiveActivityIfShowing(in app: XCUIApplication) {
        let stopButton = app.buttons["stopLiveActivity"]
        if stopButton.waitForExistence(timeout: 3) {
            stopButton.tap()
        }
        XCTAssertTrue(stopButton.waitForNonExistence(timeout: UITestTimeout.element))
    }
}
