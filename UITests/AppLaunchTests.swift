import XCTest

final class AppLaunchTests: E2ETestCase {
    @MainActor
    func testAppLaunchesAndShowsItsTitle() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
    }
}
