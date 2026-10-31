import Foundation
import Testing

/// How often a wait looks at its condition again.
///
/// A test that waits for one thing and then checks another passes only while the code under test catches up
/// during the pause of the wait. A quiet Mac gives it that time, and a busy Mac does not, so the test fails later,
/// on another machine. `make test-waits` runs the tests in the two paces of a busy Mac, set by `TROME_TEST_WAITS`:
/// - `eager`: the wait looks again after a bare `Task.yield()`, so it sees its condition at the first moment it
///   holds, as when the code under test runs late;
/// - `late`: the wait looks again after 50 ms, so the timers of the code under test fire before the test goes on,
///   as when the test itself runs late.
enum WaitPace: String {
    case normal
    case eager
    case late

    static let current = WaitPace(rawValue: ProcessInfo.processInfo.environment["TROME_TEST_WAITS"] ?? "") ?? .normal

    func pause() async {
        switch self {
        case .normal:
            try? await Task.sleep(for: .milliseconds(1))
        case .eager:
            await Task.yield()
        case .late:
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Waits until `condition` holds, and records an issue at the line of the wait when it does not hold in time, so
/// that the failure shows where the test waited, not at a later check. Wait for the state that the next step reads,
/// never for an earlier one.
///
/// The limit is in real time, so that a wait for a timer of the test clock (20 ms of real time) holds in every pace.
func waitUntil(
    _ comment: Comment? = nil,
    timeout: Duration = .seconds(10),
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            Issue.record(
                comment ?? "The condition of this wait never held in \(timeout).",
                sourceLocation: sourceLocation
            )
            return
        }
        await WaitPace.current.pause()
    }
}

/// Checks that `condition` stays false for `duration` of real time, and records an issue at its line as soon as it
/// holds: a step that must not come (one more call, a retry) gets that long to come, as a 20 ms timer of the test
/// clock fires many times in it.
func expectNever(
    _ comment: Comment? = nil,
    for duration: Duration = .seconds(1),
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let end = clock.now.advanced(by: duration)
    while clock.now < end {
        guard !condition() else {
            Issue.record(
                comment ?? "The condition of this check held, and it never should.",
                sourceLocation: sourceLocation
            )
            return
        }
        await WaitPace.current.pause()
    }
}
