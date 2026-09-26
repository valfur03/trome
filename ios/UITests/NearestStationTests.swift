import CoreLocation
import XCTest

final class NearestStationTests: E2ETestCase {
    @MainActor
    func testShowsTheNearestStationOnceLocationIsAllowed() {
        let app = makeApp()
        app.resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.8585, longitude: 2.3474))

        app.launch()
        answerPermissionPrompts(in: app)
        let testingTools = app.buttons["testingTools"]
        XCTAssertTrue(testingTools.waitForExistence(timeout: UITestTimeout.element))
        testingTools.tap()

        let stationName = app.staticTexts["nearestStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(stationName.label, "Châtelet")
        XCTAssertTrue(app.staticTexts["nearestStationLines"].label.contains("Metro 14"))
    }
}
