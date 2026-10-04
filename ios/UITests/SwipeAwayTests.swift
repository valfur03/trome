// Seam: the rider swipes the real Live Activity away in the Notification Center (the same view as the
// lock screen), with the app in the background, and iOS tells the app (ActivityKit `activityStateUpdates`).
// The app then pauses that station: the rider sees the Live Activity start at another station, and not come
// back at the swiped station after leaving it and coming back. Then the rider stands still at that station for
// longer than the app trusts a position, opens the app and cancels the pause: by the resume rule, the app asks iOS
// for a fresh position (Core Location sends none while the phone does not move), and the Live Activity of that
// station comes back.
// Why not cheaper: unit tests check the pause rules with a fake removal and a fake position; only iOS removes
// a Live Activity on a swipe and tells the app, and only Core Location says whether a fresh position comes
// while the phone stands still.
import CoreLocation
import XCTest

final class SwipeAwayTests: E2ETestCase {
    private static let liege = CLLocation(latitude: 48.879648, longitude: 2.327028)
    private static let cadet = CLLocation(latitude: 48.876018, longitude: 2.344616)
    private static let clearButtonLabels = ["Clear", "Dismiss", "Close", "Remove"]
    private static let longerThanThePositionTrust: TimeInterval = 25

    @MainActor
    func testASwipeOfTheLiveActivityPausesItsStationButNotTheOtherStations() {
        let app = makeApp()
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)
        cancelThePauseIfAny(in: app)
        moveThePhone(to: Self.liege)
        XCTAssertTrue(waitFor(shownStation(in: app)))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        openNotificationCenter(over: springboard)
        XCTAssertTrue(waitFor(liveActivityStation("Liège")))
        swipeTheLiveActivityAway()
        closeNotificationCenter()

        bringToFront(app)
        XCTAssertTrue(waitForNo(shownStation(in: app)))
        moveThePhone(to: Self.cadet)
        XCTAssertTrue(waitFor(shownStation(in: app)))
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Cadet")))

        moveThePhone(to: Self.liege)
        XCTAssertTrue(
            waitForNo(liveActivity),
            "The Live Activity came back at Liège after the swipe: \(liveActivity.label)"
        )
        closeNotificationCenter()

        standStillLongerThanTheAppTrustsAPosition()
        bringToFront(app)
        tap(app.buttons["cancelStationPause"])
        openNotificationCenter(over: app)
        XCTAssertTrue(
            waitFor(liveActivityStation("Liège")),
            "The Live Activity did not come back at Liège after the cancel of the pause"
        )
        closeNotificationCenter()
    }

    @MainActor
    private func standStillLongerThanTheAppTrustsAPosition() {
        RunLoop.current.run(until: Date().addingTimeInterval(Self.longerThanThePositionTrust))
    }

    @MainActor
    private func swipeTheLiveActivityAway() {
        liveActivity.swipeLeft()
        let clearButtons = Self.clearButtonLabels.map { springboard.buttons[$0] }
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while liveActivity.exists, Date() < deadline {
            if let clearButton = clearButtons.first(where: \.exists) {
                clearButton.tap()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(waitForNo(liveActivity), "The swipe did not remove the Live Activity")
    }

    @MainActor
    private func cancelThePauseIfAny(in app: XCUIApplication) {
        let cancelPause = app.buttons["cancelStationPause"]
        if cancelPause.exists {
            cancelPause.tap()
            XCTAssertTrue(waitForNo(cancelPause))
        }
    }
}
