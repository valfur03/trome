import CoreLocation
import XCTest

final class NearestStationTests: E2ETestCase {
    @MainActor
    func testShowsTheNearestStationOnceLocationIsAllowed() {
        let app = makeApp()
        app.resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.8585, longitude: 2.3474))

        app.launch()
        allowLocationAccess()
        let testingTools = app.buttons["testingTools"]
        XCTAssertTrue(testingTools.waitForExistence(timeout: UITestTimeout.element))
        testingTools.tap()

        let stationName = app.staticTexts["nearestStationName"]
        XCTAssertTrue(stationName.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(stationName.label, "Châtelet")
        XCTAssertTrue(app.staticTexts["nearestStationLines"].label.contains("Metro 14"))
    }

    @MainActor
    private func allowLocationAccess() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.alerts.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 10) {
            allowButton.tap()
        }
    }
}
