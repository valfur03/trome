import CoreLocation
import XCTest

/// Takes the captures of the film, in the language of the Simulator: for each station of the film, the Live
/// Activity on the lock screen, with the fake trains, as a rider sees it when they look at the phone.
/// `make film-captures` runs it through `ios/scripts/store-screenshots.sh capture`, and the film shows each capture
/// whole, in Apple's iPhone bezel.
final class FilmCaptureTests: XCTestCase {
    private struct Stop {
        let name: String
        let station: String
        let position: CLLocation
    }

    /// One card per place, each a real station with its own lines. `FILM_CAPTURES` in `ios/Makefile` lists the
    /// same names, and the storyboard of the film says why each place is there.
    private static let stops = [
        // A line alone: line 3, the first card of the film.
        Stop(name: "parmentier", station: "Parmentier", position: CLLocation(latitude: 48.865203, longitude: 2.374701)),
        // A station with several lines (4, 8, 9): the card shows the first one, and "+2".
        Stop(
            name: "strasbourg",
            station: "Strasbourg - Saint-Denis",
            position: CLLocation(latitude: 48.869509, longitude: 2.353884)
        ),
        // A line with a branch: line 7 forks after Maison Blanche.
        Stop(name: "pont-neuf", station: "Pont Neuf", position: CLLocation(latitude: 48.858501, longitude: 2.341743)),
        // An RER line, with its rows of times.
        Stop(name: "luxembourg", station: "Luxembourg", position: CLLocation(latitude: 48.845432, longitude: 2.339809)),
        // The fast cuts: line 6.
        Stop(name: "corvisart", station: "Corvisart", position: CLLocation(latitude: 48.829801, longitude: 2.350448))
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
    func testTakeTheCapturesOfTheFilm() {
        let app = XCUIApplication()
        app.launchArguments += [
            "--reset-location-source", "--fake-trains", "--end-live-activity", "--hide-testing-tools"
        ]
        XCUIDevice.shared.location = XCUILocation(location: ScreenshotSteps.farFromAnyStation)
        app.launch()
        steps.answerThePermissionQuestions()
        steps.turnOnTheAutomaticMode(in: app)

        for (index, stop) in Self.stops.enumerated() {
            if index > 0 {
                steps.launchAgain(app)
            }
            steps.showTheLiveActivity(of: stop.station, at: stop.position, in: app)
            XCUIDevice.shared.press(.home)
            steps.openNotificationCenter()
            // The station is not read on the card: after the switch to French, iOS can keep the card as a
            // placeholder for its accessibility while it shows. The app said which station it shows, and each
            // capture is checked by eye.
            steps.waitForTheLiveActivity(of: stop.station, showing: nil)
            let attachment = XCTAttachment(screenshot: steps.stillScreenshot())
            attachment.name = "lock-\(stop.name)-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.activate()
            steps.stopTheLiveActivity(in: app)
        }
    }
}
