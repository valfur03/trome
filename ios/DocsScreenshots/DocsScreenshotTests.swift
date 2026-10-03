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

    private static let farFromAnyStation = CLLocation(latitude: 48.42, longitude: 2.63)
    private static let allowLiveActivitiesAnswers = ["Always Allow", "Toujours autoriser", "Allow", "Autoriser"]

    private let timeout: TimeInterval = 30

    @MainActor
    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
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
        XCUIDevice.shared.location = XCUILocation(location: Self.farFromAnyStation)
        app.launch()
        turnOnTheAutomaticMode(in: app)

        for screenshot in Self.liveActivityScreenshots {
            showTheLiveActivity(of: screenshot, in: app)
            XCUIDevice.shared.press(.home)
            openNotificationCenter()
            waitForTheLiveActivity(of: screenshot)
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
            stopTheLiveActivity(in: app)
        }
    }

    @MainActor
    private func turnOnTheAutomaticMode(in app: XCUIApplication) {
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

    @MainActor
    private func shownStation(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["liveActivityStationName"]
    }

    @MainActor
    private func showTheLiveActivity(of screenshot: LiveActivityScreenshot, in app: XCUIApplication) {
        XCUIDevice.shared.location = XCUILocation(location: screenshot.position)
        let station = shownStation(in: app)
        XCTAssertTrue(
            waitUntil { station.exists && station.label.contains(screenshot.station) },
            "The Live Activity of \(screenshot.station) did not start with the app open at the station"
        )
    }

    @MainActor
    private func stopTheLiveActivity(in app: XCUIApplication) {
        XCUIDevice.shared.location = XCUILocation(location: Self.farFromAnyStation)
        XCTAssertTrue(
            shownStation(in: app).waitForNonExistence(timeout: timeout),
            "The Live Activity did not end when the phone left the station"
        )
    }

    @MainActor
    private func waitForTheLiveActivity(of screenshot: LiveActivityScreenshot) {
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
        for text in [screenshot.station] + screenshot.destinations {
            let element = liveActivity.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", text))
                .firstMatch
            XCTAssertTrue(
                element.waitForExistence(timeout: timeout),
                "The Live Activity of \(screenshot.station) does not show \(text)"
            )
        }
    }

    @MainActor
    private func openNotificationCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.001))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(springboard.otherElements["lockscreen-date-view"].waitForExistence(timeout: timeout))
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    @MainActor
    private func saveScreenshot(named name: String) {
        save(XCUIScreen.main.screenshot(), named: name)
    }

    @MainActor
    private func saveStillScreenshot(named name: String) {
        var screenshot = XCUIScreen.main.screenshot()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let next = XCUIScreen.main.screenshot()
            if next.pngRepresentation == screenshot.pngRepresentation {
                break
            }
            screenshot = next
        }
        save(screenshot, named: name)
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
