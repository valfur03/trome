import XCTest

class E2ETestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-location-source")
        return app
    }
}
