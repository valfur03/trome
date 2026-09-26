import CoreLocation
import XCTest

final class ArrivalNotificationTests: E2ETestCase {
    private static let abbesses = CLLocation(latitude: 48.88439, longitude: 2.33838)

    @MainActor
    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    @MainActor
    func testTappingTheArrivalNotificationOfTheAppInTheBackgroundShowsTheLiveActivity() {
        let app = makeApp()
        app.launch()
        allowLocationAccessIfAsked()
        allowNotificationsIfAsked()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
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

    @MainActor
    private func allowLocationAccessIfAsked() {
        let allowButton = springboard.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }

    @MainActor
    private func allowNotificationsIfAsked() {
        let allowButton = springboard.alerts.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }
    }
}
