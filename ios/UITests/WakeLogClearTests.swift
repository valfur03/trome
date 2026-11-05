// Seam: iOS presents the confirmation of the trash of the Wake log away from Share and the trash; its Cancel button
// keeps every line, and its destructive button erases them.
// The log can be the only record of a walk, and the trash sits next to Share, so one slip must not erase it.
// Why not cheaper: the app code only asks SwiftUI for a confirmation; whether iOS shows it, where it places it,
// and how it is cancelled is iOS's own behaviour, which no unit test can run.
// Seam, on the way: the launch of a tap, as iOS reports it to the app. Its screen must come to the front within the
// first seconds, so that the record tells a tap, never a wake of iOS; and the built app names its commit, which the
// build writes in its Info.plist. Why not cheaper: when iOS sends the screen at launch is iOS's own behaviour (it
// reports the app in the background before the screen of a tap comes), and only a real build runs the build script.
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
        let tap = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Opened by the rider: on screen'"))
        XCTAssertTrue(waitFor(tap.firstMatch), "The Wake log does not tell this launch as the rider's open")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Started by iOS'")).firstMatch.exists,
            "The Wake log tells a tap as a start by iOS"
        )
        let build = NSPredicate(format: "label MATCHES '(?s)App launched: build [0-9]+, commit [0-9a-f]{7}.*, iOS .*'")
        XCTAssertTrue(
            app.staticTexts.matching(build).firstMatch.exists,
            "The line of the launch does not name the build, its commit and the iOS version"
        )
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
