import XCTest

extension XCUIApplication {
    @MainActor
    static func withRealGPS() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-location-source")
        return app
    }
}
