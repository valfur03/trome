import XCTest

final class LocationSourceResetTests: E2ETestCase {
    @MainActor
    func testANewRunStartsWithTheRealGPSAfterAFakePositionWasSaved() {
        let firstRun = makeApp()
        launch(firstRun)
        firstRun.buttons["testingTools"].tap()
        firstRun.buttons["farFromAnyStation"].tap()
        XCTAssertTrue(firstRun.staticTexts["Fake: Far from any station (Fontainebleau forest)"]
            .waitForExistence(timeout: UITestTimeout.element))
        firstRun.terminate()

        let secondRun = makeApp()
        launch(secondRun)
        secondRun.buttons["testingTools"].tap()
        let source = secondRun.staticTexts["locationSource"]
        XCTAssertTrue(source.waitForExistence(timeout: UITestTimeout.element))
        XCTAssertEqual(source.label, "Real GPS")
    }
}
