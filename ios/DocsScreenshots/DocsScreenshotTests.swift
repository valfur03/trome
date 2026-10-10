import CoreLocation
import XCTest

final class DocsScreenshotTests: XCTestCase {
    private struct LiveActivityScreenshot {
        let name: String
        let station: String
        let position: CLLocation
        let destinations: [String]
        var savesTheIsland = false
    }

    private static let liveActivityScreenshots = [
        LiveActivityScreenshot(
            name: "live-activity-metro",
            station: "Saint-Paul (Le Marais)",
            position: CLLocation(latitude: 48.855237, longitude: 2.360878),
            destinations: ["La Défense", "Château de Vincennes"],
            savesTheIsland: true
        ),
        LiveActivityScreenshot(
            name: "live-activity-fork",
            station: "Pont Neuf",
            position: CLLocation(latitude: 48.858501, longitude: 2.341743),
            destinations: ["La Courneuve - 8 Mai 1945", "Mairie d'Ivry", "Villejuif - Louis Aragon"]
        ),
        LiveActivityScreenshot(
            name: "live-activity-rer",
            station: "Luxembourg",
            position: CLLocation(latitude: 48.845432, longitude: 2.339809),
            destinations: ["Aéroport Charles de Gaulle 2 TGV", "Mitry - Claye", "Robinson", "Saint-Rémy-lès-Chevreuse"]
        )
    ]

    private let timeout: TimeInterval = 30

    @MainActor
    private var steps: ScreenshotSteps {
        ScreenshotSteps()
    }

    @MainActor
    private var springboard: XCUIApplication {
        steps.springboard
    }

    private var language: String {
        ProcessInfo.processInfo.environment["DOCS_LANGUAGE"] ?? "en"
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
    func testTakeTheScreenshotsOfTheDocs() {
        if language == "en" {
            takeTheScreenshotsOfTheApp()
        }
        takeTheScreenshotsOfTheLiveActivity()
    }

    @MainActor
    private func takeTheScreenshotsOfTheApp() {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-location-source")
        app.launch()

        let location = app.descendants(matching: .any)["locationPermissionStatus"]
        let notifications = app.descendants(matching: .any)["notificationsPermissionStatus"]
        answerPermissionQuestions {
            location.exists && location.label == "Location, Always"
                && notifications.exists && notifications.label == "Notifications, On"
        }
        XCTAssertTrue(app.switches["automaticModeToggle"].waitForExistence(timeout: timeout))
        saveScreenshot(named: "app-main-screen")

        app.buttons["testingTools"].tap()
        XCTAssertTrue(app.buttons["useRealGPS"].waitForExistence(timeout: timeout))
        saveScreenshot(named: "app-testing-tools")
        app.terminate()
    }

    @MainActor
    private func takeTheScreenshotsOfTheLiveActivity() {
        let app = XCUIApplication()
        app.launchArguments += ["--reset-location-source", "--fake-trains", "--end-live-activity"]
        XCUIDevice.shared.location = XCUILocation(location: ScreenshotSteps.farFromAnyStation)
        app.launch()
        steps.turnOnTheAutomaticMode(in: app)

        for screenshot in Self.liveActivityScreenshots {
            steps.showTheLiveActivity(of: screenshot.station, at: screenshot.position, in: app)
            XCUIDevice.shared.press(.home)
            steps.openNotificationCenter()
            steps.waitForTheLiveActivity(of: screenshot.station, showing: screenshot.destinations)
            saveStillScreenshot(named: "\(screenshot.name)-\(language)")
            XCUIDevice.shared.press(.home)
            if screenshot.savesTheIsland {
                let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
                settings.activate()
                XCTAssertTrue(settings.wait(for: .runningForeground, timeout: timeout))
                sleep(2)
                saveStillScreenshot(named: "live-activity-island-\(language)")
                settings.terminate()
            }
            app.activate()
            steps.stopTheLiveActivity(in: app)
        }
    }

    @MainActor
    private func saveScreenshot(named name: String) {
        save(XCUIScreen.main.screenshot(), named: name)
    }

    @MainActor
    private func saveStillScreenshot(named name: String) {
        save(steps.stillScreenshot(), named: name)
    }

    @MainActor
    private func save(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func answerPermissionQuestions(until isSettled: () -> Bool) {
        let answers: [(button: String, screenshot: String?)] = [
            (button: "Allow While Using App", screenshot: "app-location-permission"),
            (button: "Change to Always Allow", screenshot: "app-always-permission"),
            (button: "Allow", screenshot: "app-notification-permission")
        ]
        var savedScreenshots: Set<String> = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !isSettled() {
            for answer in answers where springboard.buttons[answer.button].exists {
                if let screenshot = answer.screenshot, !savedScreenshots.contains(screenshot) {
                    saveStillScreenshot(named: screenshot)
                    savedScreenshots.insert(screenshot)
                }
                springboard.buttons[answer.button].tap()
            }
            sleep(1)
        }
        XCTAssertTrue(isSettled(), "The location and notification permissions did not settle")
        XCTAssertEqual(
            savedScreenshots,
            ["app-location-permission", "app-always-permission", "app-notification-permission"],
            "The location, Always and notification questions were not all on screen"
        )
    }
}
