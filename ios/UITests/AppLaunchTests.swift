import XCTest

final class AppLaunchTests: E2ETestCase {
    @MainActor
    func testAppLaunchesAndShowsItsTitle() {
        let app = makeApp()
        launch(app)

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
    }
}
