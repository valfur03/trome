import CoreLocation
import XCTest

class E2ETestCase: XCTestCase {
    static let farFromAnyStation = CLLocation(latitude: 48.42, longitude: 2.63)
    private static let permissionAnswers = ["Allow While Using App", "Keep Only While Using", "Allow"]
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
        XCTAssertTrue(waitFor(app.staticTexts["appTitle"]))
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
                terminateWithItsRelaunches(app)
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
        XCTAssertTrue(waitFor(title))
    }

    @MainActor
    func waitFor(_ element: XCUIElement) -> Bool {
        element.exists || element.waitForExistence(timeout: UITestTimeout.element)
    }

    @MainActor
    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitFor(element), "\(element) did not show", file: file, line: line)
        element.tap()
    }

    @MainActor
    func waitForNo(_ element: XCUIElement) -> Bool {
        !element.exists || element.waitForNonExistence(timeout: UITestTimeout.element)
    }

    @MainActor
    func waitForFirst(of elements: [XCUIElement]) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        repeat {
            if let element = elements.first(where: \.exists) {
                return element
            }
        } while Date() < deadline
        return nil
    }

    @MainActor
    func stopLiveActivityIfShowing(in app: XCUIApplication) {
        let stopButton = app.buttons["stopLiveActivity"]
        let showButton = app.buttons["showNearestStationLiveActivity"]
        let shown = waitForFirst(of: [stopButton, showButton])
        XCTAssertNotNil(shown)
        if shown === stopButton {
            stopButton.tap()
        }
        XCTAssertTrue(waitFor(showButton))
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
