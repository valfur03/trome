import Foundation
import Testing
@testable import TROMECore

struct ReportedArrivalRulesTests {
    private let station = Station(id: "s", name: "S", coordinate: Coordinate(48.8500, 2.3500), lines: [])
    private let insideTheArea = Coordinate(48.8505, 2.3500)
    private let insideTheStopArea = Coordinate(48.8520, 2.3500)
    private let outsideTheStopArea = Coordinate(48.8534, 2.3500)
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func fix(at coordinate: Coordinate, accuracy: Double = 10, secondsAgo: TimeInterval = 0) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: accuracy, timestamp: now.addingTimeInterval(-secondsAgo))
    }

    private func confirmed(by known: PositionFix?) -> PositionFix? {
        ReportedArrivalRules.position(confirming: station, with: known, now: now)
    }

    @Test func aTrustedPositionInTheAreaConfirmsTheReport() {
        #expect(confirmed(by: fix(at: insideTheArea)) == fix(at: insideTheArea))
        #expect(confirmed(by: fix(at: insideTheArea, secondsAgo: 120)) == fix(at: insideTheArea, secondsAgo: 120))
    }

    @Test func aTrustedPositionInTheStopAreaPutsThePhoneAtTheStation() {
        #expect(confirmed(by: fix(at: insideTheStopArea)) == fix(at: station.coordinate, accuracy: 0))
    }

    @Test func noTrustedPositionAtTheStationIsNoArrival() {
        #expect(confirmed(by: nil) == nil)
        #expect(confirmed(by: fix(at: insideTheArea, accuracy: 500)) == nil)
        #expect(confirmed(by: fix(at: insideTheArea, secondsAgo: 121)) == nil)
        #expect(confirmed(by: fix(at: outsideTheStopArea)) == nil)
    }

    @Test func onlyATrustedPositionOfTheLast15SecondsSettlesAReport() {
        #expect(ReportedArrivalRules.settles(fix(at: outsideTheStopArea, secondsAgo: 15), now: now))
        #expect(!ReportedArrivalRules.settles(fix(at: outsideTheStopArea, secondsAgo: 16), now: now))
        #expect(!ReportedArrivalRules.settles(fix(at: outsideTheStopArea, accuracy: 101), now: now))
        #expect(!ReportedArrivalRules.settles(nil, now: now))
    }

    @Test func onlyATrustedPositionOfTheLast15SecondsMakesARefusalFinal() {
        #expect(ReportedArrivalRules.isFinal(refusalWith: fix(at: outsideTheStopArea, secondsAgo: 15), now: now))
        #expect(!ReportedArrivalRules.isFinal(refusalWith: fix(at: outsideTheStopArea, secondsAgo: 100), now: now))
        #expect(!ReportedArrivalRules.isFinal(refusalWith: fix(at: insideTheArea, accuracy: 500), now: now))
        #expect(!ReportedArrivalRules.isFinal(refusalWith: nil, now: now))
    }

    @Test func saysWhyAReportIsNoArrival() {
        let refusal = { (known: PositionFix?) in
            ReportedArrivalRules.refusal(at: station, position: known, now: now)
        }

        #expect(refusal(nil) == "No arrival at S: iOS gave no position")
        let rough = fix(at: insideTheArea, accuracy: 500, secondsAgo: 30)
        #expect(refusal(rough) == "No arrival at S: the position is ±500 m and 30 s old")
        #expect(refusal(fix(at: outsideTheStopArea)) == "No arrival at S: the position is 378 m away")
    }
}
