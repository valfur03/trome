import CoreLocation
import XCTest

/// The steps that the docs pictures, the store pictures and the captures of the film share: turn on the automatic mode, put the Live
/// Activity of a station on the lock screen with the fake trains, show it, and take a still screenshot.
@MainActor
struct ScreenshotSteps {
    static let farFromAnyStation = CLLocation(latitude: 48.42, longitude: 2.63)
    private static let allowLiveActivitiesAnswers = ["Always Allow", "Toujours autoriser", "Allow", "Autoriser"]
    /// The buttons of the permission questions of iOS, in English and in French.
    private static let permissionAnswers = [
        "Allow While Using App", "Change to Always Allow", "Allow",
        "Autoriser pendant l’utilisation de l’app", "Passer à Toujours autoriser", "Autoriser"
    ]

    let timeout: TimeInterval = 30

    var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// Answers the questions of iOS that show (the first run on a reset Simulator), until none shows for 3 s.
    func answerThePermissionQuestions() {
        let answers = springboard.buttons.matching(NSPredicate(format: "label IN %@", Self.permissionAnswers))
        var quietSince = Date()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, Date().timeIntervalSince(quietSince) < 3 {
            if answers.firstMatch.exists {
                answers.firstMatch.tap()
                quietSince = Date()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertFalse(answers.firstMatch.exists, "A permission question of iOS stayed on the screen")
    }

    func turnOnTheAutomaticMode(in app: XCUIApplication) {
        let toggle = app.switches["automaticModeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        if toggle.value as? String == "0" {
            toggle.switches.firstMatch.tap()
        }
        let cancelSnooze = app.buttons["cancelSnooze"]
        if cancelSnooze.exists {
            cancelSnooze.tap()
        }
        XCTAssertTrue(app.buttons["snoozeMenu"].waitForExistence(timeout: timeout), "The automatic mode is not on")
        XCTAssertTrue(shownStation(in: app).waitForNonExistence(timeout: timeout), "A Live Activity still shows")
    }

    /// The fake trains count from the launch, so a picture taken minutes into the run would show shorter waits, or
    /// the next train. A new launch before each picture gives it the waits of a fresh launch, as on the pages.
    func launchAgain(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        turnOnTheAutomaticMode(in: app)
    }

    func shownStation(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["liveActivityStationName"]
    }

    func showTheLiveActivity(of station: String, at position: CLLocation, in app: XCUIApplication) {
        XCUIDevice.shared.location = XCUILocation(location: position)
        let shown = shownStation(in: app)
        XCTAssertTrue(
            waitUntil { shown.exists && shown.label.contains(station) },
            "The Live Activity of \(station) did not start with the app open at the station"
        )
    }

    func stopTheLiveActivity(in app: XCUIApplication) {
        XCUIDevice.shared.location = XCUILocation(location: Self.farFromAnyStation)
        XCTAssertTrue(
            shownStation(in: app).waitForNonExistence(timeout: timeout),
            "The Live Activity did not end when the phone left the station"
        )
    }

    /// Waits until the lock screen shows a Live Activity, and answers the question of iOS to allow
    /// Live Activities when it shows. With `texts`, also waits until the Live Activity shows each of them.
    func waitForTheLiveActivity(of station: String, showing texts: [String]?) {
        let liveActivity = springboard.otherElements["activity-content-view"]
        XCTAssertTrue(
            liveActivity.waitForExistence(timeout: timeout),
            "No Live Activity showed in the Notification Center"
        )
        let allowLiveActivities = springboard.buttons
            .matching(NSPredicate(format: "label IN %@", Self.allowLiveActivitiesAnswers))
            .firstMatch
        if allowLiveActivities.waitForExistence(timeout: 3) {
            allowLiveActivities.tap()
            XCTAssertTrue(
                allowLiveActivities.waitForNonExistence(timeout: timeout),
                "The question to allow Live Activities stayed on the lock screen"
            )
        }
        guard let texts else { return }
        for text in [station] + texts {
            let element = liveActivity.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", text))
                .firstMatch
            XCTAssertTrue(
                element.waitForExistence(timeout: timeout),
                "The Live Activity of \(station) does not show \(text)"
            )
        }
    }

    func openNotificationCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(springboard.otherElements["lockscreen-date-view"].waitForExistence(timeout: timeout))
    }

    func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// A screenshot of a screen that has stopped moving: two screenshots in a row are the same, or 5 s passed.
    func stillScreenshot() -> XCUIScreenshot {
        var screenshot = XCUIScreen.main.screenshot()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let next = XCUIScreen.main.screenshot()
            if next.pngRepresentation == screenshot.pngRepresentation {
                break
            }
            screenshot = next
        }
        return screenshot
    }
}
