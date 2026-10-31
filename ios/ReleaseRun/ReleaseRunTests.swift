import XCTest

// Seam: iOS starts the app as the store ships it (the Release build: no Testing tools, no PRIM key) and draws its
// first screen. Every commit of main must be safe to ship, so make merge runs it on the commit that becomes main.
// Why not cheaper: the E2E suite runs the Debug build, and make check only compiles the Release one, so a fault of the
// Release build alone (a start that fails with no key, a Testing tool left outside #if DEBUG) passes every other check.
// Fake: Config/ReleaseRun.xcconfig gives the app a server host that never answers, as the server is not the seam; the
// release guide checks the Release build with the real server values before each upload (make release-server-check).
final class ReleaseRunTests: XCTestCase {
    private static let firstScreenTimeout: TimeInterval = 60
    /// What the store app must not show: the Testing tools of the Debug build (their link, the banner of a fake
    /// position), and each part of a rider feature that merged before the feature is ready (the change that turns the
    /// feature on removes it from this list).
    private static let hiddenIdentifiers = ["testingTools", "fakePositionBanner"]
    private static let hiddenLabels = ["Testing tools"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testTheStoreAppStartsOnItsFirstScreenWithNothingHidden() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "The Release app did not start (state \(app.state.rawValue)); a crash is in ios/.build/release-run.xcresult"
        )
        XCTAssertTrue(
            app.staticTexts["appTitle"].waitForExistence(timeout: Self.firstScreenTimeout),
            "The Release app did not reach its first screen: no title after \(Int(Self.firstScreenTimeout)) s"
        )
        let hidden = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@ OR label IN[c] %@", Self.hiddenIdentifiers, Self.hiddenLabels)
        )
        let shown = hidden.allElementsBoundByIndex.map { "'\($0.label)' (\($0.identifier))" }
        XCTAssertTrue(shown.isEmpty, "The Release app shows what it must hide: \(shown.joined(separator: ", "))")
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "The Release app stopped after its first screen (state \(app.state.rawValue))"
        )
    }
}
