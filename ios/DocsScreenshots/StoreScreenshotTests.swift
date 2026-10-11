import CoreLocation
import XCTest

/// Takes the captures of the store pictures, in the language of the Simulator: the main screen of the app,
/// then, for each station of the set, the Dynamic Island on the Home Screen and the Live Activity on the
/// lock screen, with the fake trains. `ios/scripts/store-screenshots.sh` runs it and composes the pictures.
final class StoreScreenshotTests: XCTestCase {
    private struct Stop {
        let name: String
        let station: String
        let position: CLLocation
    }

    /// The order of the store set: a plain metro line, a line with a branch, an RER line.
    private static let stops = [
        Stop(
            name: "metro",
            station: "Goncourt",
            position: CLLocation(latitude: 48.869886, longitude: 2.370861)
        ),
        Stop(
            name: "fork",
            station: "Pont Neuf",
            position: CLLocation(latitude: 48.858501, longitude: 2.341743)
        ),
        Stop(
            name: "rer",
            station: "Luxembourg",
            position: CLLocation(latitude: 48.845432, longitude: 2.339809)
        )
    ]

    /// The buttons of the permission questions of iOS, in English and in French.
    private static let permissionAnswers = [
        "Allow While Using App", "Change to Always Allow", "Allow",
        "Autoriser pendant l’utilisation de l’app", "Passer à Toujours autoriser", "Autoriser"
    ]

    @MainActor
    private var steps: ScreenshotSteps {
        ScreenshotSteps()
    }

    private var language: String {
        ProcessInfo.processInfo.environment["STORE_LANGUAGE"] ?? "en"
    }

    override static func setUp() {
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
    func testTakeTheCapturesOfTheStorePictures() {
        let app = XCUIApplication()
        app.launchArguments += [
            "--reset-location-source", "--fake-trains", "--end-live-activity", "--hide-testing-tools"
        ]
        XCUIDevice.shared.location = XCUILocation(location: ScreenshotSteps.farFromAnyStation)
        app.launch()
        answerThePermissionQuestions(in: app)
        steps.turnOnTheAutomaticMode(in: app)
        XCTAssertTrue(app.buttons["seeAnExample"].isEnabled, "The row See an example is not enabled")
        XCTAssertFalse(app.buttons["testingTools"].exists, "The link to the Testing tools shows")
        let helpLink = app.descendants(matching: .any)["helpLink"].firstMatch
        XCTAssertTrue(helpLink.isHittable, "The link Help and feedback is not on the screen")
        let screen = steps.stillScreenshot()
        save(screen, named: "app")
        // The store picture of the app ends just under this link: the rows of the caption show, the footer not.
        saveTheRows(of: helpLink, in: screen, named: "app-help-row")

        for stop in Self.stops {
            steps.showTheLiveActivity(of: stop.station, at: stop.position, in: app)
            XCUIDevice.shared.press(.home)
            steps.openNotificationCenter()
            // The texts of the card are not read here: after the switch to French, the accessibility of iOS
            // can keep the card as a placeholder for minutes while it shows. The app already said which station
            // it shows, and each picture is checked by eye.
            steps.waitForTheLiveActivity(of: stop.station, showing: nil)
            save(steps.stillScreenshot(), named: "lock-\(stop.name)")
            // The lock screen comes first: it answers the question of iOS to allow Live Activities, and only
            // then does the Dynamic Island show the Live Activity on the Home Screen.
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(steps.springboard.wait(for: .runningForeground, timeout: steps.timeout))
            sleep(2)
            save(steps.stillScreenshot(), named: "island-\(stop.name)")
            app.activate()
            steps.stopTheLiveActivity(in: app)
        }
    }

    /// Answers the questions of iOS that show (the first run on a reset Simulator), then checks that the
    /// main screen shows the permissions given: Location Always and Notifications On, in English.
    @MainActor
    private func answerThePermissionQuestions(in app: XCUIApplication) {
        let answers = steps.springboard.buttons.matching(NSPredicate(format: "label IN %@", Self.permissionAnswers))
        var quietSince = Date()
        let deadline = Date().addingTimeInterval(steps.timeout)
        while Date() < deadline, Date().timeIntervalSince(quietSince) < 3 {
            if answers.firstMatch.exists {
                answers.firstMatch.tap()
                quietSince = Date()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertFalse(answers.firstMatch.exists, "A permission question of iOS stayed on the screen")
        guard language == "en" else { return }
        let location = app.descendants(matching: .any)["locationPermissionStatus"]
        let notifications = app.descendants(matching: .any)["notificationsPermissionStatus"]
        XCTAssertTrue(
            steps.waitUntil { location.label == "Location, Always" && notifications.label == "Notifications, On" },
            "The permissions are not Location Always and Notifications On"
        )
    }

    /// Saves the rows of the screenshot that the element covers, in pixels, so that the composition cuts
    /// the screen at the same place in every language.
    @MainActor
    private func saveTheRows(of element: XCUIElement, in screenshot: XCUIScreenshot, named name: String) {
        let scale = screenshot.image.scale
        let frame = element.frame
        let attachment = XCTAttachment(string: "\(Int(frame.minY * scale)) \(Int(frame.maxY * scale))")
        attachment.name = "\(name)-\(language)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func save(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(language)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
