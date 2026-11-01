// Seam: iOS presents the confirmation of the trash of the Wake log away from Share and the trash; its Cancel button
// keeps every line, and its destructive button erases them.
// The log can be the only record of a walk, and the trash sits next to Share, so one slip must not erase it.
// Why not cheaper: the app code only asks SwiftUI for a confirmation; whether iOS shows it, where it places it,
// and how it is cancelled is iOS's own behaviour, which no unit test can run.
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
        let launchLine = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Phone at launch'")).firstMatch
        XCTAssertTrue(waitFor(launchLine), "The Wake log does not show the line of this launch")
        let trash = app.buttons["wakeLogClear"]
        let confirm = app.alerts.buttons["Clear"]
        let share = app.navigationBars.buttons["Share…"]
        XCTAssertTrue(waitFor(share) && waitFor(trash))
        let toolbarSpots = share.frame.union(trash.frame)

        tap(trash)
        XCTAssertTrue(waitFor(confirm), "The trash did not ask for a confirmation")
        XCTAssertFalse(
            confirm.frame.intersects(toolbarSpots),
            "The confirmation covers Share or the trash, where a second quick tap would erase the log"
        )
        tap(app.alerts.buttons["Cancel"])
        XCTAssertTrue(waitForNo(confirm))
        XCTAssertTrue(launchLine.exists, "Cancelling the confirmation erased the Wake log")

        tap(trash)
        tap(confirm)
        XCTAssertTrue(waitForNo(launchLine), "Confirming did not erase the Wake log")
    }
}
