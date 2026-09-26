import CoreLocation
import XCTest

class E2ETestCase: XCTestCase {
    static let farFromAnyStation = CLLocation(latitude: 48.42, longitude: 2.63)
    private static let permissionAnswers = [
        "Allow While Using App", "Keep Only While Using", "Change to Always Allow", "Allow"
    ]
    private static let allowedLocationLabels = ["Location, Always", "Location, While Using the App"]
    @MainActor private static var permissionsAreSettled = false

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    @MainActor
    func makeApp() -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: Self.farFromAnyStation)
        let app = XCUIApplication()
        app.launchArguments.append("--reset-location-source")
        terminateWithItsRelaunches(app)
        return app
    }

    @MainActor
    private func terminateWithItsRelaunches(_ app: XCUIApplication) {
        for _ in 0..<3 where app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .runningBackground, timeout: 1)
        }
    }

    @MainActor
    func launch(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
        if Self.permissionsAreSettled {
            answerPermissionPrompt()
        } else {
            settlePermissions(in: app, resettingRefusedLocation: true)
        }
    }

    @MainActor
    func answerPermissionPrompts(in app: XCUIApplication) {
        settlePermissions(in: app, resettingRefusedLocation: false)
    }

    @MainActor
    private func settlePermissions(in app: XCUIApplication, resettingRefusedLocation: Bool) {
        let location = locationStatus(in: app)
        let notifications = notificationsStatus(in: app)
        var mayResetLocation = resettingRefusedLocation
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while Date() < deadline {
            answerPermissionPrompt()
            guard location.exists, notifications.exists else {
                app.swipeUp()
                continue
            }
            if Self.allowedLocationLabels.contains(location.label), notifications.label == "Notifications, On" {
                Self.permissionsAreSettled = true
                scrollToTop(of: app)
                return
            }
            if mayResetLocation, location.label == "Location, Off" {
                mayResetLocation = false
                app.resetAuthorizationStatus(for: .location)
                app.launch()
                continue
            }
            _ = springboard.alerts.firstMatch.waitForExistence(timeout: 1)
        }
        XCTFail("The location and notification permissions did not settle")
    }

    @MainActor
    private func answerPermissionPrompt() {
        for answer in Self.permissionAnswers where springboard.buttons[answer].exists {
            let button = springboard.buttons[answer]
            button.tap()
            _ = button.waitForNonExistence(timeout: 2)
        }
    }

    @MainActor
    private func scrollToTop(of app: XCUIApplication) {
        let title = app.staticTexts["appTitle"]
        for _ in 0..<3 where !(title.exists && title.isHittable) {
            app.swipeDown()
        }
        XCTAssertTrue(title.waitForExistence(timeout: UITestTimeout.element))
    }

    @MainActor
    private func locationStatus(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["locationPermissionStatus"]
    }

    @MainActor
    private func notificationsStatus(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["notificationsPermissionStatus"]
    }
}
