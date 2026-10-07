import Foundation
import Testing
@testable import TROMECore

@MainActor
struct WakeLogTests {
    let storage = InMemoryKeyValueStore()
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func showsTheNewestEntryFirstAndKeepsItAfterARelaunch() {
        let log = WakeLog(storage: storage, now: { [start] in start })
        log.record(.launch, "first")
        log.record(.decision, "second")

        let relaunched = WakeLog(storage: storage)

        #expect(relaunched.entries.map(\.text) == ["second", "first"])
        #expect(relaunched.entries.map(\.kind) == [.decision, .launch])
        #expect(relaunched.entries.first?.date == start)
    }

    @Test func dropsTheOldestEntriesOverTheLimit() {
        let log = WakeLog(storage: storage)
        for index in 0...WakeLog.maximumEntries {
            log.record(.system, "\(index)")
        }

        #expect(log.entries.count == WakeLog.maximumEntries)
        #expect(log.entries.first?.text == "\(WakeLog.maximumEntries)")
        #expect(log.entries.last?.text == "1")
    }

    @Test func clearsForGood() {
        let log = WakeLog(storage: storage)
        log.record(.launch, "first")

        log.clear()

        #expect(log.entries.isEmpty)
        #expect(WakeLog(storage: storage).entries.isEmpty)
    }

    @Test func skipsALineThatRepeatsTheLastOneOfItsKindWhenAsked() {
        let log = WakeLog(storage: storage)
        log.record(.regions, "plan 1")
        log.record(.decision, "decision")
        log.record(.regions, "plan 1", unlessRepeated: true)
        log.record(.regions, "plan 2", unlessRepeated: true)
        log.record(.decision, "decision")

        #expect(log.entries.map(\.text) == ["decision", "plan 2", "decision", "plan 1"])
    }
}
