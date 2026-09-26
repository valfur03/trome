import XCTest

final class AppLaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndShowsItsTitle() {
        let app = XCUIApplication.withRealGPS()
        app.launch()

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: UITestTimeout.element))
    }
}
