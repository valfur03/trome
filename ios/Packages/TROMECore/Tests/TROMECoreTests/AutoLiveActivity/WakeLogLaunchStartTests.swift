import Foundation
import Testing
@testable import TROMECore

/// A walk is read from its record alone: each launch says how it began, a tap of the rider or a run by iOS with no
/// screen, so that a tap is never told as a wake of iOS (the walk of 2026-11-02 could not tell them apart).
@MainActor
@Suite(.bounded)
struct WakeLogLaunchStartTests {
    let storage = InMemoryKeyValueStore()
    let clock = TestClock()
    let build = AppBuild(infoDictionary: ["CFBundleVersion": "6", AppBuild.commitKey: "1e2e704"])
    let launchLine = "App launched: build 6, commit 1e2e704, iOS 26.1\nLocation: Always, precise"

    let preparedLaunchLine =
        "App launched: build 6, commit 1e2e704, iOS 26.1, prepared in advance by iOS\nLocation: Always, precise"

    private func launch(preparedInAdvance: Bool = false) -> WakeLog {
        let log = WakeLog(storage: storage, now: { [clock] in clock.now })
        log.recordLaunch(
            build, iOSVersion: "26.1", phone: ["Location: Always, precise"], preparedInAdvance: preparedInAdvance
        )
        return log
    }

    private func lines(_ log: WakeLog) -> [String] {
        log.entries.filter { $0.kind == .launch }.map(\.text)
    }

    @Test func tellsATapWhenAScreenComesWithinTheFirstSeconds() {
        let log = launch()
        clock.advance(by: 0.4)

        log.recordScreenOnFront()
        clock.advance(by: 5)
        log.recordOpenWindowEnd()

        #expect(lines(log) == ["Opened by the rider: on screen 0.4 s after the launch", "App on screen", launchLine])
        #expect(!log.entries.contains { $0.text.contains("Started by iOS") || $0.text.contains("iOS ran the app") })
    }

    @Test func tellsAScreenAtTheEndOfTheWindowAsATap() {
        let log = launch()
        clock.advance(by: 5)

        log.recordScreenOnFront()

        #expect(lines(log).first == "Opened by the rider: on screen 5.0 s after the launch")
    }

    @Test func tellsARunOfIOSWhenNoScreenComesInTheWindow() {
        let log = launch()
        clock.advance(by: 5)

        log.recordOpenWindowEnd()

        #expect(lines(log) == ["iOS ran the app: no screen of the app came to the front in its first 5 s", launchLine])
    }

    @Test func tellsTheRiderOpeningTheAppLaterAfterARunOfIOS() {
        let log = launch()
        clock.advance(by: 5)
        log.recordOpenWindowEnd()
        clock.advance(by: 12 * 60)

        log.recordScreenOnFront()
        let opened = log.entries[0]

        #expect(opened.text == "Opened by the rider 12 min after iOS ran the app")
        #expect(opened.date == clock.now)
        #expect(lines(log).dropFirst(2).first == LaunchStart.noScreenLine)
    }

    /// iOS can suspend the app before the end of the window runs: the screen of a later open then comes first.
    @Test func tellsBothLinesWhenTheEndOfTheWindowRunsLateAfterASuspension() {
        let log = launch()
        clock.advance(by: 20 * 60)

        log.recordScreenOnFront()
        log.recordOpenWindowEnd()

        #expect(lines(log) == [
            "Opened by the rider 20 min after iOS ran the app",
            "iOS ran the app: no screen of the app came to the front in its first 5 s",
            "App on screen",
            launchLine
        ])
    }

    @Test func tellsAsUnknownALaunchThatStoppedBeforeItToldHowItBegan() {
        _ = launch()

        let next = launch()

        #expect(lines(next) == [launchLine, LaunchStart.unknownLine, launchLine])
    }

    @Test func tellsNothingUnknownAfterALaunchThatToldHowItBegan() {
        let first = launch()
        clock.advance(by: 5)
        first.recordOpenWindowEnd()

        let next = launch()

        #expect(!next.entries.contains { $0.text == LaunchStart.unknownLine })
    }

    /// The record keeps a bounded number of lines: a launch tells how it began in two lines at most, whatever comes,
    /// and one more when iOS prepared it in advance, the line of its resume.
    @Test(arguments: [false, true]) func writesAtMostTwoLinesOfHowALaunchBegan(preparedInAdvance: Bool) {
        let log = launch(preparedInAdvance: preparedInAdvance)
        for _ in 0..<10 {
            log.recordLaunchResumed()
            log.recordOpenWindowEnd()
            clock.advance(by: 60)
            log.recordScreenOnFront()
        }

        let told = lines(log).filter { $0 != "App on screen" && $0 != launchLine && $0 != preparedLaunchLine }
        #expect(told.count == (preparedInAdvance ? 3 : 2))
    }

    /// iOS can prepare the app hours before a tap (a prewarm): the tap must still read as the rider's open, counted
    /// from the moment that iOS resumed the app, never as a run of iOS with no screen.
    @Test func tellsATapOnALaunchThatIOSPreparedInAdvanceAsTheRidersOpen() {
        let log = launch(preparedInAdvance: true)
        clock.advance(by: 2 * 3600)
        log.recordLaunchResumed()
        let resumedAt = clock.now
        clock.advance(by: 0.3)

        log.recordScreenOnFront()
        clock.advance(by: 5)
        log.recordOpenWindowEnd()

        #expect(lines(log) == [
            "Opened by the rider: on screen 0.3 s after the launch",
            "App on screen",
            WakeLog.resumedLine,
            preparedLaunchLine
        ])
        #expect(log.launchedAt == resumedAt)
    }

    @Test func countsFromTheScreenWhenItComesBeforeTheResumeOfAPreparedLaunch() {
        let log = launch(preparedInAdvance: true)
        clock.advance(by: 2 * 3600)

        log.recordScreenOnFront()
        log.recordLaunchResumed()

        #expect(lines(log).first == "Opened by the rider: on screen 0.0 s after the launch")
        #expect(lines(log).filter { $0 == WakeLog.resumedLine }.count == 1)
    }

    @Test func tellsARunOfIOSOnALaunchThatIOSPreparedInAdvance() {
        let log = launch(preparedInAdvance: true)
        clock.advance(by: 3600)
        log.recordLaunchResumed()
        clock.advance(by: 5)

        log.recordOpenWindowEnd()

        #expect(lines(log).first == LaunchStart.noScreenLine)
    }

    /// iOS may drop a launch that it prepared and never resumed: no line of it is unknown, as it never began.
    @Test func tellsNothingUnknownAfterAPreparedLaunchThatIOSNeverResumed() {
        _ = launch(preparedInAdvance: true)

        let next = launch()

        #expect(lines(next) == [launchLine, preparedLaunchLine])
    }

    @Test func writesNoResumeLineForALaunchThatIOSDidNotPrepare() {
        let log = launch()
        let launchedAt = log.launchedAt
        clock.advance(by: 0.4)

        log.recordLaunchResumed()
        log.recordScreenOnFront()

        #expect(lines(log) == ["Opened by the rider: on screen 0.4 s after the launch", "App on screen", launchLine])
        #expect(log.launchedAt == launchedAt)
    }
}
