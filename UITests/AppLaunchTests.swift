import XCTest

final class AppLaunchTests: E2ETestCase {
    @MainActor
    func testAppLaunchesAndShowsItsTitle() {
        let app = XCUIApplication.withRealGPS()
        app.launch()

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
    }
}
