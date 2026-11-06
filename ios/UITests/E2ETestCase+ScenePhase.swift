import XCTest

extension E2ETestCase {
    /// The mark of `UITestScenePhaseMark` in the app.
    private static let scenePhaseIdentifier = "uiTestScenePhase"

    /// iOS keeps the app inactive until the end of its own animation (the Notification Center that slides away, the
    /// app that opens), and drops a tap that comes then: twice, a tap 0.5 s before the app was active opened nothing.
    /// The Notification Center leaves the screen up to a second before that end, so the test waits for the app itself.
    @MainActor
    func waitUntilIOSMakesActive(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let scenePhase = app.descendants(matching: .any)[Self.scenePhaseIdentifier]
        let isActive = NSPredicate(format: "value == %@", "active")
        let active = XCTNSPredicateExpectation(predicate: isActive, object: scenePhase)
        XCTAssertEqual(
            XCTWaiter().wait(for: [active], timeout: UITestTimeout.element),
            .completed,
            "iOS did not make the app active, so it would drop a tap on it",
            file: file,
            line: line
        )
    }
}
