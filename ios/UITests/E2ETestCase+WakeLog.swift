import XCTest

// The wake log of the Testing tools is the one place that shows an arrival decided in the background: a build of
// the Simulator has no silent start, and the app sends no notification, so it writes there why nothing started.
extension E2ETestCase {
    private static let mostSwipesThroughTheWakeLog = 40

    /// The wake log keeps the lines of earlier runs, so a test clears it before it reads it. New lines may come at
    /// once (the plan of the station areas), so the test waits only for the line that it reads to go.
    @MainActor
    func openAnEmptyWakeLog(in app: XCUIApplication, expectingNo line: XCUIElement) {
        tap(app.buttons["testingTools"])
        XCTAssertTrue(waitFor(app.navigationBars["Testing tools"]))
        let wakeLog = app.buttons["wakeLog"]
        for _ in 0..<5 where !(wakeLog.exists && wakeLog.isHittable) {
            app.swipeUp()
        }
        tap(wakeLog)
        let trash = app.buttons["wakeLogClear"]
        XCTAssertTrue(waitFor(trash))
        if trash.isEnabled {
            tap(trash)
            tap(app.alerts.buttons["Clear"])
        }
        XCTAssertTrue(waitForNo(line))
    }

    /// The list draws only the rows on screen, so the test scrolls down the log to its oldest line: the bottom is
    /// where a swipe no longer changes the last row.
    @MainActor
    func wakeLogShows(_ line: XCUIElement, in app: XCUIApplication) -> Bool {
        let list = app.collectionViews.firstMatch
        var lastRow = ""
        for _ in 0..<Self.mostSwipesThroughTheWakeLog {
            if line.exists {
                return true
            }
            let texts = list.staticTexts
            let count = texts.count
            let row = count < 2 ? "" : texts.element(boundBy: count - 2).label + texts.element(boundBy: count - 1).label
            if row == lastRow {
                return false
            }
            lastRow = row
            list.swipeUp()
        }
        return line.exists
    }

    /// The line that a background arrival with no start writes, in place of the notification of earlier builds.
    @MainActor
    func noStartLine(at station: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "No start at \(station),"))
            .firstMatch
    }
}
