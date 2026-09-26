import XCTest

final class AppLaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsItsTitle() {
        let app = XCUIApplication.withRealGPS()
        app.launch()

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 10))
    }
}
