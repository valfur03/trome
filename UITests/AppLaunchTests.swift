import XCTest

final class AppLaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsItsTitle() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 10))
    }
}
