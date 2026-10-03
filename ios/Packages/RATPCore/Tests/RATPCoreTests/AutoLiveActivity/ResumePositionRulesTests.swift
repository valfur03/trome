import Foundation
import Testing
@testable import RATPCore

struct ResumePositionRulesTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let station = AutoTestPlaces.fiftyMetersFromA

    private func fix(age: TimeInterval, accuracy: Double = 10) -> PositionFix {
        PositionFix(coordinate: station, accuracyMeters: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    @Test func usesAPrecisePositionOfAtMost15SecondsWithNoWait() {
        #expect(ResumePositionRules.usesWithoutWaiting(fix(age: 15), now: now))
    }

    @Test(arguments: [16.0, 60.0])
    func asksIOSWhenTheHeldPositionIsOlderThan15Seconds(age: TimeInterval) {
        #expect(!ResumePositionRules.usesWithoutWaiting(fix(age: age), now: now))
    }

    @Test func asksIOSWhenTheHeldPositionIsImprecise() {
        #expect(!ResumePositionRules.usesWithoutWaiting(fix(age: 0, accuracy: 300), now: now))
    }

    @Test func asksIOSWhenThereIsNoHeldPosition() {
        #expect(!ResumePositionRules.usesWithoutWaiting(nil, now: now))
    }

    @Test func prefersThePositionOfIOS() {
        let fresh = fix(age: 0)

        #expect(ResumePositionRules.position(fresh: fresh, held: fix(age: 60), now: now) == fresh)
    }

    @Test func fallsBackToAHeldPositionOfAtMost2Minutes() {
        let held = fix(age: 120)

        #expect(ResumePositionRules.position(fresh: nil, held: held, now: now) == held)
    }

    @Test func usesNoHeldPositionOlderThan2Minutes() {
        #expect(ResumePositionRules.position(fresh: nil, held: fix(age: 121), now: now) == nil)
    }

    @Test func usesNoImprecisePosition() {
        let imprecise = fix(age: 0, accuracy: 300)

        #expect(ResumePositionRules.position(fresh: imprecise, held: imprecise, now: now) == nil)
    }

    @Test func fallsBackToTheHeldPositionWhenThePositionOfIOSIsImprecise() {
        let held = fix(age: 60)

        #expect(ResumePositionRules.position(fresh: fix(age: 0, accuracy: 300), held: held, now: now) == held)
    }

    @Test func usesNoPositionWhenThereIsNone() {
        #expect(ResumePositionRules.position(fresh: nil, held: nil, now: now) == nil)
    }
}
