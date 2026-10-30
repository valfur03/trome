import XCTest

// Before a test kills the app, the app ends its location work (its background sessions and its position stream),
// and locationd gets the end. When the app is killed while it streams positions, locationd keeps the stream and
// starts the app again in the background to serve it. On a busy Mac that start can come seconds later, in the
// middle of the next launch, which then fails with "No such process". So the test sends the app to the background
// and posts `end` (a Darwin notification that Debug builds observe); the app ends its location work and posts
// `ended` once locationd has answered a request sent after the end.
extension E2ETestCase {
    private enum LocationEndSignal {
        static let end = "TROME.UITests.location.end"
        static let ended = "TROME.UITests.location.ended"
    }

    @MainActor private static var locationEnded = false
    @MainActor private static var listensToTheApp = false

    @MainActor
    func endTheLocationWork(of app: XCUIApplication) {
        guard app.state != .notRunning else { return }
        // An app that iOS started by itself may be suspended, and would get the end only once it runs again.
        if app.state != .runningForeground {
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITestTimeout.element))
        }
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        listenToTheApp()
        Self.locationEnded = false
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(LocationEndSignal.end as CFString),
            nil,
            nil,
            true
        )
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while !Self.locationEnded, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(
            Self.locationEnded,
            "The app did not confirm the end of its location work, so a kill could leave a position stream "
                + "that starts the app again"
        )
    }

    @MainActor
    private func listenToTheApp() {
        guard !Self.listensToTheApp else { return }
        Self.listensToTheApp = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in E2ETestCase.locationEnded = true }
            },
            LocationEndSignal.ended as CFString,
            nil,
            .deliverImmediately
        )
    }
}
