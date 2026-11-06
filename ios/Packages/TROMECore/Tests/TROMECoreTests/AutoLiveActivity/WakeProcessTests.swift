import Foundation
import Testing
@testable import TROMECore

/// Each wake line tells a fresh launch by iOS from an event that came to a running app: the log of a walk with no
/// such word could not tell why a station gave nothing.
@Suite(.bounded)
struct WakeProcessTests {
    let launch = Date(timeIntervalSince1970: 1_000_000)

    @Test func tellsAFreshLaunchForTheFirstEventSoonAfterTheLaunch() {
        var process = WakeProcess(launchedAt: launch)

        #expect(process.line(now: launch + 3) == "fresh launch, 3 s ago")
    }

    @Test func tellsARunningAppForTheNextEvents() {
        var process = WakeProcess(launchedAt: launch)
        _ = process.line(now: launch + 3)

        #expect(process.line(now: launch + 20) == "app already running for 20 s")
        #expect(process.line(now: launch + 600) == "app already running for 10 min")
        #expect(process.line(now: launch + 7_500) == "app already running for 2 h 05 min")
    }

    @Test func tellsARunningAppForAFirstEventLongAfterTheLaunch() {
        var process = WakeProcess(launchedAt: launch)

        #expect(process.line(now: launch + WakeProcess.freshLaunchWindow + 1) == "app already running for 31 s")
    }
}
