import CoreLocation
import XCTest

class E2ETestCase: XCTestCase {
    static let farFromAnyStation = CLLocation(latitude: 48.42, longitude: 2.63)

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allowButton = alert.buttons["Allow"]
            guard allowButton.exists else { return false }
            allowButton.tap()
            return true
        }
    }

    @MainActor
    func makeApp() -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: Self.farFromAnyStation)
        let app = XCUIApplication()
        app.launchArguments.append("--reset-location-source")
        return app
    }
}
