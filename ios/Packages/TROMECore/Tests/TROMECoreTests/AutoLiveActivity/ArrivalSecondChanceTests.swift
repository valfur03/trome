import Foundation
import Testing
@testable import TROMECore

struct ArrivalSecondChanceTests {
    private let station = Station(id: "s", name: "S", coordinate: Coordinate(48.8500, 2.3500), lines: [])
    private let insideTheArea = Coordinate(48.8505, 2.3500)
    private let insideTheStopArea = Coordinate(48.8520, 2.3500)
    private let outsideTheStopArea = Coordinate(48.8534, 2.3500)
    private let reportedAt = Date(timeIntervalSince1970: 1_000_000)

    private var chance: ArrivalSecondChance {
        ArrivalSecondChance(station: station, reportedAt: reportedAt)
    }

    private func verdict(at coordinate: Coordinate, accuracy: Double = 10, secondsAgo: TimeInterval = 0)
        -> ArrivalSecondChance.Verdict {
        let now = reportedAt + 30
        let fix = PositionFix(coordinate: coordinate, accuracyMeters: accuracy, timestamp: now - secondsAgo)
        return chance.verdict(on: fix, now: now)
    }

    @Test func onlyAFreshTrustedPositionWithin150MetersPutsTheRiderAtTheStation() {
        #expect(verdict(at: insideTheArea) == .atTheStation)
        #expect(verdict(at: insideTheStopArea) == .undecided)
        #expect(verdict(at: insideTheArea, accuracy: 101) == .undecided)
        #expect(verdict(at: insideTheArea, secondsAgo: 16) == .undecided)
        #expect(chance.verdict(on: nil, now: reportedAt) == .undecided)
    }

    @Test func aFreshTrustedPositionPastTheStopAreaIsFar() {
        #expect(verdict(at: outsideTheStopArea) == .far(meters: 378))
        #expect(verdict(at: outsideTheStopArea, accuracy: 500) == .undecided)
    }

    @Test func isOverTwoMinutesAfterTheReport() {
        #expect(!chance.isOver(now: reportedAt + 119))
        #expect(chance.isOver(now: reportedAt + 120))
    }

    @Test func saysHowItEnded() {
        let now = reportedAt + 42
        let other = Station(id: "o", name: "O", coordinate: Coordinate(48.8500, 2.3540), lines: [])
        let rough = PositionFix(coordinate: insideTheArea, accuracyMeters: 500, timestamp: now - 3)

        #expect(chance.startLine == "Second chance at S: asks iOS for a position for up to 120 s")
        #expect(chance.line(for: .outcome(.notified(station)), now: now) == "Second chance at S: notified after 42 s")
        #expect(chance.line(for: .outcome(.started(station)), now: now)
            == "Second chance at S: Live Activity started after 42 s")
        #expect(chance.line(for: .outcome(.notified(other)), now: now)
            == "Second chance at S: ended after 42 s: Notified: O")
        #expect(chance.line(for: .far(meters: 400), now: now)
            == "Second chance at S: gave up after 42 s: the position is 400 m away")
        #expect(chance.line(for: .left, now: now)
            == "Second chance at S: gave up after 42 s: iOS says the phone left its area")
        #expect(chance.line(for: .limit(lastPosition: rough), now: now)
            == "Second chance at S: gave up after 42 s: the position is ±500 m and 3 s old")
        #expect(chance.line(for: .limit(lastPosition: nil), now: now)
            == "Second chance at S: gave up after 42 s: iOS gave no position")
        #expect(chance.line(for: .fakePosition, now: now)
            == "Second chance at S: gave up after 42 s: a fake position is on")
        #expect(chance.line(for: .automaticStartOff, now: now)
            == "Second chance at S: gave up after 42 s: the automatic start is snoozed or off")
    }
}
