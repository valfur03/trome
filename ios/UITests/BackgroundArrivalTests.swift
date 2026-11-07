// Seam: the phone reaches a station while the app is in the background, as in a rider's pocket, and iOS reports
// the area of the station: the app decides the arrival from the background, and iOS shows no notification of the
// app. The rider then opens the app at the station, and sees the real Live Activity of that station.
// The app runs as on a rider's phone: the location "Always", its second process since the grant, and the
// background long enough for iOS to stop its position stream (about 10 s), so no position reaches it before the
// report. No launch argument keeps it awake or following the position.
// The Simulator cannot watch areas (in the iOS 27 Simulator, `isMonitoringAvailable` is false), so the test posts
// the report in place of iOS (`UITestRegionWake`, debug builds only): the app runs its own handler of a report,
// from the background, with the last position of iOS, once that position is inside the area (the Simulator takes
// seconds to give the app a new position on a busy Mac, and iOS reports an area only from its own position).
// Not guarded: the wake of a closed or suspended app by iOS, which QA and the iPhone check; iOS never suspends an
// app that an XCUITest launched.
// The wake log is the one place that shows the decision in the background: a build of the Simulator has no silent
// start, and the app opened at the station starts the Live Activity from its own position too.
// Why not cheaper: unit tests decide a report with a fake position provider; only iOS says whether it gives a
// position to an app in the background, shows no notification, and draws the Live Activity.
import CoreLocation
import XCTest

final class BackgroundArrivalTests: E2ETestCase {
    private static let julesJoffrin = CLLocation(latitude: 48.892453, longitude: 2.344614)
    private static let julesJoffrinArrivalArea = "arrival:IDFM:22054"
    /// 445 m west of Jules Joffrin, its nearest station: the app on screen plans the area of Jules Joffrin, and
    /// starts nothing.
    private static let nearJulesJoffrin = CLLocation(latitude: 48.893853, longitude: 2.338914)
    /// iOS stops the stream about 10 s after the app leaves the screen; the rest is a margin for a busy Mac.
    private static let longerThanIOSKeepsTheStreamOffScreen: TimeInterval = 20
    private static let enteredSignalPrefix = "TROME.UITests.region.entered."
    private static let handledSignal = "TROME.UITests.region.handled"
    @MainActor private static var reportIsHandled = false
    @MainActor private static var listensToTheApp = false

    @MainActor
    func testAnArrivalInTheBackgroundShowsNoNotificationAndOpeningTheAppThereShowsTheLiveActivity() {
        let app = makeApp()
        addTeardownBlock { @MainActor in self.resetLocationAuthorization(of: app) }
        launchWithLocationAlways(app)
        terminateWithItsRelaunches(app)
        launch(app)
        waitUntilTheLaunchEndedTheLiveActivity(in: app)
        moveThePhone(to: Self.nearJulesJoffrin)
        openAnEmptyWakeLog(in: app, expectingNo: noStartLine(at: "Jules Joffrin", in: app))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: UITestTimeout.element))
        let inThePocket = XCTestExpectation(description: "the phone stays in the pocket")
        _ = XCTWaiter.wait(for: [inThePocket], timeout: Self.longerThanIOSKeepsTheStreamOffScreen)
        moveThePhone(to: Self.julesJoffrin)
        reportTheArrival(inArea: Self.julesJoffrinArrivalArea)

        openNotificationCenter(over: springboard, expectingALiveActivity: false)
        XCTAssertFalse(notificationOfTheApp.exists, "A notification of the app came at the station")
        closeNotificationCenter()

        bringToFront(app)
        XCTAssertTrue(waitFor(app.navigationBars["Wake log"]))
        XCTAssertTrue(
            wakeLogShows(noStartLine(at: "Jules Joffrin", in: app), in: app),
            "The app in the background did not decide the arrival that iOS reported at Jules Joffrin"
        )
        openNotificationCenter(over: app)
        XCTAssertTrue(waitFor(liveActivityStation("Jules Joffrin")))
        XCTAssertFalse(notificationOfTheApp.exists, "A notification of the app came with the Live Activity")
        closeNotificationCenter()
    }

    /// Does what iOS does when the phone enters the area of a station that the app watches, and waits until the
    /// handler of the app returns.
    @MainActor
    private func reportTheArrival(inArea regionId: String) {
        listenToTheApp()
        Self.reportIsHandled = false
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName((Self.enteredSignalPrefix + regionId) as CFString),
            nil,
            nil,
            true
        )
        let deadline = Date().addingTimeInterval(UITestTimeout.element)
        while !Self.reportIsHandled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(Self.reportIsHandled, "The app did not handle the report: it does not watch \(regionId)")
    }

    @MainActor
    private func listenToTheApp() {
        guard !Self.listensToTheApp else { return }
        Self.listensToTheApp = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in BackgroundArrivalTests.reportIsHandled = true }
            },
            Self.handledSignal as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// The arrival notification that earlier builds sent (its title is the station), or any notification of the
    /// app, alone or in a stack (iOS starts its label with the name of the app).
    @MainActor
    private var notificationOfTheApp: XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(
                format: "(identifier == %@ AND label == %@) OR (identifier == %@ AND label BEGINSWITH %@)",
                "NotificationTitle", "Jules Joffrin", "NotificationShortLookView", "TROME"
            ))
            .firstMatch
    }
}
