import CoreLocation
import XCTest

final class LiveActivityTests: E2ETestCase {
    private static let nearEiffelTower = CLLocation(latitude: 48.8584, longitude: 2.2945)

    @MainActor
    func testUserCanShowTheLiveActivityOfTheNearestStationAndStopIt() {
        let app = makeApp()
        launch(app)
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
        XCTAssertFalse(app.buttons["chooseStation"].exists)
        XCTAssertFalse(app.buttons["changeStation"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["departureRow"].exists)

        let stopButton = app.buttons["stopLiveActivity"]
        if stopButton.waitForExistence(timeout: 3) {
            stopButton.tap()
        }
        let showButton = app.buttons["showNearestStationLiveActivity"]
        XCTAssertTrue(showButton.waitForExistence(timeout: UITestTimeout.element))
        showButton.tap()
        let problem = app.staticTexts["nearestStationProblem"]
        XCTAssertTrue(problem.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertTrue(problem.label.hasPrefix("No metro or RER station was found"))

        XCUIDevice.shared.location = XCUILocation(location: Self.nearEiffelTower)
        showButton.tap()
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(lockScreenStation.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Champ de Mars Tour Eiffel")
        XCTAssertFalse(app.staticTexts["liveActivityError"].exists)
        XCTAssertFalse(stopButton.waitForNonExistence(timeout: 5))

        stopButton.tap()
        XCTAssertTrue(showButton.waitForExistence(timeout: UITestTimeout.element))
    }
}
