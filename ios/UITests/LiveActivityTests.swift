import CoreLocation
import XCTest

final class LiveActivityTests: E2ETestCase {
    private static let nearEiffelTower = CLLocation(latitude: 48.8584, longitude: 2.2945)

    @MainActor
    func testUserAllowsLocationThenShowsTheLiveActivityOfTheNearestStationAndStopsIt() {
        let app = makeApp()
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        answerPermissionPrompts(in: app)
        XCTAssertFalse(app.buttons["chooseStation"].exists)
        XCTAssertFalse(app.buttons["changeStation"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["departureRow"].exists)

        stopLiveActivityIfShowing(in: app)
        let showButton = app.buttons["showNearestStationLiveActivity"]
        tap(showButton)
        let problem = app.staticTexts["nearestStationProblem"]
        XCTAssertTrue(waitFor(problem))
        XCTAssertTrue(problem.label.hasPrefix("No metro or RER station was found"))

        XCUIDevice.shared.location = XCUILocation(location: Self.nearEiffelTower)
        waitUntilTheAppFinds("Champ de Mars Tour Eiffel", in: app)
        tap(showButton)
        let lockScreenStation = app.staticTexts["liveActivityStationName"]
        XCTAssertTrue(waitFor(lockScreenStation))
        XCTAssertEqual(lockScreenStation.label, "On the lock screen: Champ de Mars Tour Eiffel")
        XCTAssertFalse(app.staticTexts["liveActivityError"].exists)

        tap(app.buttons["stopLiveActivity"])
        XCTAssertTrue(waitFor(showButton))
    }

    @MainActor
    private func waitUntilTheAppFinds(_ stationName: String, in app: XCUIApplication) {
        tap(app.buttons["testingTools"])
        let found = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "nearestStationName", stationName))
            .firstMatch
        XCTAssertTrue(waitFor(found))
        tap(app.navigationBars.buttons.firstMatch)
        XCTAssertTrue(waitFor(app.staticTexts["appTitle"]))
    }
}
