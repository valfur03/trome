import XCTest

extension E2ETestCase {
    private static let alwaysAllowedAnswer = "Change to Always Allow"

    /// Launches the app with the location "Always", the access of a rider whose closed app wakes at stations.
    /// End the test with `resetLocationAuthorization(of:)`, so that the next test gets "While Using the App" again.
    @MainActor
    func launchWithLocationAlways(_ app: XCUIApplication) {
        resetLocationAuthorization(of: app)
        app.launch()
        XCTAssertTrue(waitFor(app.staticTexts["appTitle"]))
        settlePermissions(
            in: app,
            resettingRefusedLocation: false,
            expectingLocationPrompt: true,
            alwaysAnswer: Self.alwaysAllowedAnswer,
            locationLabels: ["Location, Always"]
        )
        Self.permissionsAreSettled = false
    }
}
