// Seam: the rider swipes the real Live Activity away in the Notification Center (the same view as the
// lock screen), with the app in the background, and iOS tells the app (ActivityKit `activityStateUpdates`).
// The app then pauses that station: the rider sees the Live Activity start at another station, and not come
// back at the swiped station after leaving it and coming back.
// Why not cheaper: unit tests check the pause rules with a fake removal; only iOS removes a Live Activity
// on a swipe and tells the app, and a fake cannot say when or whether it does.
import CoreLocation
import XCTest

final class SwipeAwayTests: E2ETestCase {
    private static let liege = CLLocation(latitude: 48.879648, longitude: 2.327028)
    private static let cadet = CLLocation(latitude: 48.876018, longitude: 2.344616)
    private static let clearButtonLabels = ["Clear", "Dismiss", "Close", "Remove"]

    @MainActor
    func testASwipeOfTheLiveActivityPausesItsStationButNotTheOtherStations() {
        let app = makeApp()
        launch(app)
        stopLiveActivityIfShowing(in: app)
        cancelThePauseIfAny(in: app)
        moveThePhone(to: Self.liege)
        XCTAssertTrue(waitFor(app.buttons["stopLiveActivity"]))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        openNotificationCenter(over: springboard)
        XCTAssertTrue(waitFor(liveActivityStation("Liège")))
        swipeTheLiveActivityAway()
        closeNotificationCenter()

        app.activate()
        XCTAssertTrue(waitFor(app.buttons["showNearestStationLiveActivity"]))
        moveThePhone(to: Self.cadet)
        XCTAssertTrue(waitFor(app.buttons["stopLiveActivity"]))
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Cadet")))

        moveThePhone(to: Self.liege)
        XCTAssertTrue(
            waitForNo(liveActivity),
            "The Live Activity came back at Liège after the swipe: \(liveActivity.label)"
        )
        closeNotificationCenter()

        app.activate()
        cancelThePauseIfAny(in: app)
        stopLiveActivityIfShowing(in: app)
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
