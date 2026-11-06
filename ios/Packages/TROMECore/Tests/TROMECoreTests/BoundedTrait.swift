import Foundation
import Testing

/// Runs the tests of the suites with this trait at most as many at once as the Mac has cores. Every suite of these
/// tests has it, and `BoundedTraitTests` fails when one lacks it.
///
/// Swift Testing starts every test at once unless the run sets a bound, and the tests of the main actor then share
/// its one thread: on a busy Mac, hundreds of tests wait in turn on that thread, and a wait of 10 s (`waitUntil`) runs
/// out while it serves the others. A bound on the suites that wait is not enough: the other tests still start at once
/// and take that thread. The `make` commands set the bound of Swift Testing, but a run of `swift test` by hand, or
/// from Xcode, does not; this trait holds the bound in every run. A wait also checks that its test holds a slot, so it
/// fails at its own line when its suite lacks the trait.
///
/// Swift Testing counts the wait for a slot in the time limit of a test, so a test with a time limit takes the next
/// free slot before the tests that wait in the queue: it waits for at most one test to end, not for the whole queue.
struct BoundedTrait: SuiteTrait, TestTrait, TestScoping {
    var slots = BoundedSlots.shared

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    /// A test that already holds a slot, through the trait of an outer suite, takes no second one: with every slot
    /// held by such tests, none would ever end.
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard !BoundedSlots.isHeld else { return try await function() }
        try await slots.withSlot(first: test.timeLimit != nil) {
            try await BoundedSlots.$isHeld.withValue(true) { try await function() }
        }
    }
}

extension Trait where Self == BoundedTrait {
    /// Runs the tests of this suite at most as many at once as the Mac has cores: every suite has it.
    static var bounded: Self { BoundedTrait() }
}

/// The slots of the tests, one per core.
actor BoundedSlots {
    static let shared = BoundedSlots(count: ProcessInfo.processInfo.activeProcessorCount)

    /// True inside a test that holds a slot.
    @TaskLocal static var isHeld = false

    private(set) var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Records an issue at the line of a wait whose test holds no slot, and says how to give it one. The wait still
    /// runs, so that the test ends as it would with a slot.
    static func checkHeld(sourceLocation: SourceLocation) {
        guard !isHeld else { return }
        Issue.record(
            "This wait runs in real time: put the trait .bounded on its suite, as in @Suite(.bounded).",
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
