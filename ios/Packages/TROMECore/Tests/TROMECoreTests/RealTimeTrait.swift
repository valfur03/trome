import Foundation
import Testing

/// Runs the tests of a suite whose tests wait in real time (`waitUntil`, `expectNever`) at most as many at once as the
/// Mac has cores, with the tests of every other suite that has this trait.
///
/// Swift Testing starts every test at once unless the run sets a bound, and the tests of the main actor then share
/// its one thread: on a busy Mac, hundreds of tests wait in turn on that thread, and a wait of 10 s runs out while it
/// serves the others. The `make` commands set the bound of Swift Testing, but a run of `swift test` by hand, or from
/// Xcode, does not; this trait holds the bound in every run. A wait checks that its test runs inside this trait, so a
/// new suite that waits and lacks it fails at once, in every run, and not only on a busy Mac.
///
/// Swift Testing counts the wait for a slot in the time limit of a test, so a test with a time limit takes the next
/// free slot before the tests that wait in the queue: it waits for at most one test to end, not for the whole queue.
struct RealTimeTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await RealTimeSlots.shared.withSlot(first: test.timeLimit != nil) {
            try await RealTimeSlots.$isHeld.withValue(true) { try await function() }
        }
    }
}

extension Trait where Self == RealTimeTrait {
    /// Runs the tests of this suite at most as many at once as the Mac has cores: put it on each suite whose tests
    /// wait in real time.
    static var realTime: Self { RealTimeTrait() }
}

/// The slots of the tests that wait in real time, one per core.
actor RealTimeSlots {
    static let shared = RealTimeSlots(count: ProcessInfo.processInfo.activeProcessorCount)

    /// True inside a test that holds a slot.
    @TaskLocal static var isHeld = false

    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Records an issue at the line of a wait whose test holds no slot, and says how to give it one. The wait still
    /// runs, so that the test ends as it would with a slot.
    static func checkHeld(sourceLocation: SourceLocation) {
        guard !isHeld else { return }
        Issue.record(
            "This wait runs in real time: put the trait .realTime on its suite, as in @Suite(.realTime).",
            sourceLocation: sourceLocation
        )
    }

    init(count: Int) {
        free = max(count, 1)
    }

    /// With `first`, the test takes the next free slot before the tests that wait in the queue.
    func withSlot(first: Bool = false, _ operation: @Sendable () async throws -> Void) async throws {
        await take(first: first)
        defer { give() }
        try await operation()
    }

    /// A wait for a slot always ends, even in a cancelled run: each test that holds a slot gives it back when it ends.
    private func take(first: Bool) async {
        if free > 0 {
            free -= 1
            return
        }
        await withCheckedContinuation { waiting.insert($0, at: first ? 0 : waiting.endIndex) }
    }

    private func give() {
        if waiting.isEmpty {
            free += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
