// Seam: iOS presents the confirmation of the trash of the Wake log, and its own way out (a Cancel button, or a tap
// outside a popover) must keep every line, while its destructive button erases them.
// The log can be the only record of a walk, and the trash sits next to Share, so one slip must not erase it.
// Why not cheaper: the app code only asks SwiftUI for a confirmation; whether iOS shows it, anchors it next to
// Share, and how it is cancelled is iOS's own behaviour, which no unit test can run.
import XCTest

final class WakeLogClearTests: E2ETestCase {
    @MainActor
    func testTheTrashErasesTheLinesOnlyAfterTheConfirmation() {
        let app = makeApp()
        launch(app)
        tap(app.buttons["testingTools"])
        let wakeLogLink = app.buttons["wakeLog"]
        for _ in 0..<5 where !(wakeLogLink.exists && wakeLogLink.isHittable) {
            app.swipeUp()
        }
        tap(wakeLogLink)
        let launchLine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'App launched'")).firstMatch
        XCTAssertTrue(waitFor(launchLine), "The Wake log does not show the line of this launch")
        let trash = app.buttons["wakeLogClear"]
        let confirm = app.buttons["Clear All"]

        tap(trash)
        XCTAssertTrue(waitFor(confirm), "The trash did not ask for a confirmation")
        cancelTheConfirmation(in: app)
        XCTAssertTrue(waitForNo(confirm))
        XCTAssertTrue(launchLine.exists, "Cancelling the confirmation erased the Wake log")

        tap(trash)
        tap(confirm)
        XCTAssertTrue(waitForNo(launchLine), "Confirming did not erase the Wake log")
    }

    /// iOS shows the confirmation as a sheet with a Cancel button, or, next to a toolbar button, as a popover that a
    /// tap outside closes: the test takes the way out that iOS gives.
    @MainActor
    private func cancelTheConfirmation(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        }
    }
}
