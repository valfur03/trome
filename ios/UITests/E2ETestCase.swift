import CoreLocation
import XCTest

class E2ETestCase: XCTestCase {
    static let farFromAnyStation = CLLocation(latitude: 48.42, longitude: 2.63)
    private static let notificationCenterIdentifier = "lockscreen-date-view"
    private static let liveActivityIdentifier = "activity-content-view"
    private static let locationPromptAnswer = "Allow While Using App"
    private static let alwaysPromptAnswer = "Keep Only While Using"
    private static let permissionAnswers = [locationPromptAnswer, alwaysPromptAnswer, "Allow"]
    private static let allowedLocationLabels = ["Location, Always", "Location, While Using the App"]
    @MainActor private static var permissionsAreSettled = false

    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            SimulatorNotificationService.waitUntilItAnswers()
        }
    }

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
        moveThePhone(to: Self.farFromAnyStation)
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
        XCTAssertTrue(waitFor(app.staticTexts["appTitle"]))
        settlePermissions(in: app, resettingRefusedLocation: false, expectingLocationPrompt: true)
    }

    @MainActor
    private func settlePermissions(
        in app: XCUIApplication,
        resettingRefusedLocation: Bool,
        expectingLocationPrompt: Bool = false
    ) {
        let location = locationStatus(in: app)
        let notifications = notificationsStatus(in: app)
        let screen = app.collectionViews.firstMatch
        var mayResetLocation = resettingRefusedLocation
        var answers: [String] = []
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while Date() < deadline {
            answers += answerPermissionPrompt()
            guard app.state == .runningForeground, screen.exists else {
                if app.state != .runningForeground {
                    app.activate()
                }
                _ = screen.waitForExistence(timeout: 1)
                continue
            }
            guard location.exists, notifications.exists else {
                screen.swipeUp()
                continue
            }
            let askedForLocation = expectingLocationPrompt || answers.contains(Self.locationPromptAnswer)
            let locationPromptsAnswered = !askedForLocation || answers.contains(Self.alwaysPromptAnswer)
            if locationPromptsAnswered, Self.allowedLocationLabels.contains(location.label),
               notifications.label == "Notifications, On" {
                if expectingLocationPrompt {
                    assertLocationPromptsCameFirst(in: answers)
                }
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
    @discardableResult
    private func answerPermissionPrompt() -> [String] {
        var answers: [String] = []
        for answer in Self.permissionAnswers where springboard.buttons[answer].exists {
            let button = springboard.buttons[answer]
            button.tap()
            _ = button.waitForNonExistence(timeout: 2)
            answers.append(answer)
        }
        return answers
    }

    private func assertLocationPromptsCameFirst(in answers: [String]) {
        let locationPrompts = [Self.locationPromptAnswer, Self.alwaysPromptAnswer]
        XCTAssertEqual(
            Array(answers.prefix(2)),
            locationPrompts,
            "The app did not ask for Always right after the first location question: \(answers)"
        )
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
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    @MainActor
    func stopLiveActivityIfShowing(in app: XCUIApplication) {
        let stopButton = app.buttons["stopLiveActivity"]
        let showButton = app.buttons["showNearestStationLiveActivity"]
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while Date() < deadline, waitForFirst(of: [stopButton, showButton]) === stopButton {
            tapWhereItIs(stopButton, in: app)
            _ = showButton.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(waitFor(showButton))
    }

    @MainActor
    private func tapWhereItIs(_ element: XCUIElement, in app: XCUIApplication) {
        guard let frame = try? element.snapshot().frame else { return }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }

    @MainActor
    func openNotificationCenter(over app: XCUIApplication, expectingALiveActivity: Bool = true) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .fast, thenHoldForDuration: 0)
        let notificationCenter = springboard.otherElements[Self.notificationCenterIdentifier]
        XCTAssertTrue(
            waitFor(notificationCenter),
            "The Notification Center did not open, or iOS renamed its SpringBoard element "
                + "'\(Self.notificationCenterIdentifier)'"
        )
        guard expectingALiveActivity else { return }
        let allowLiveActivities = springboard.buttons["Allow"]
        XCTAssertNotNil(
            waitForFirst(of: [allowLiveActivities, liveActivity]),
            "No Live Activity showed in the Notification Center, or iOS renamed its SpringBoard element "
                + "'\(Self.liveActivityIdentifier)'"
        )
        if allowLiveActivities.exists {
            allowLiveActivities.tap()
        }
    }

    @MainActor
    func closeNotificationCenter() {
        XCUIDevice.shared.press(.home)
    }

    @MainActor
    var liveActivity: XCUIElement {
        springboard.otherElements[Self.liveActivityIdentifier]
    }

    @MainActor
    func liveActivityStation(_ name: String) -> XCUIElement {
        liveActivity.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label CONTAINS %@", name, ", \(name), ")
        ).firstMatch
    }

    @MainActor
    var liveActivityPager: XCUIElement {
        liveActivity.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Show the next line")).firstMatch
    }

    @MainActor
    func liveActivityElement(containing text: String) -> XCUIElement {
        liveActivity.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    func moveThePhone(to location: CLLocation) {
        XCUIDevice.shared.location = XCUILocation(location: location)
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
