import Foundation
import Testing
@testable import TROMECore

/// The number that a wait reads on the Live Activity, as its countdown runs: a metro wait reads the whole minutes left,
/// rounded down, like the platform screens of the metro; an RER wait keeps its round-up.
struct TrainCountdownTests {
    let trainTime = Date(timeIntervalSince1970: 1_000_000)
    let line4 = TransitLine(mode: .metro, name: "4", stopIds: ["IDFM:40"])

    func at(secondsLeft seconds: TimeInterval) -> Date {
        trainTime.addingTimeInterval(-seconds)
    }

    var train: LineDirection.Train {
        LineDirection.Train(time: trainTime, destination: "Porte de Clignancourt")
    }

    @Test(arguments: [
        (secondsLeft: 180.0, reads: 3),
        (secondsLeft: 179, reads: 2),
        (secondsLeft: 150, reads: 2),
        (secondsLeft: 120, reads: 2),
        (secondsLeft: 119, reads: 1),
        (secondsLeft: 60, reads: 1),
        (secondsLeft: 59.9, reads: 0),
        (secondsLeft: 59, reads: 0),
        (secondsLeft: 0, reads: 0)
    ])
    func aMetroWaitReadsTheWholeMinutesLeftRoundedDown(secondsLeft: TimeInterval, reads: Int) {
        #expect(train.countdownMinutes(at: at(secondsLeft: secondsLeft), on: .metro) == reads)
        #expect(train.countdownEnd(on: .metro) == trainTime)
    }

    @Test func aMetroWaitGoesThreeTwoOneZeroWithNoMinuteSkipped() {
        let shown = stride(from: 180.0, through: 0, by: -0.5).map { secondsLeft in
            train.countdownMinutes(at: at(secondsLeft: secondsLeft), on: .metro)
        }

        #expect(shown.reduce(into: [Int]()) { readings, minutes in
            if readings.last != minutes { readings.append(minutes) }
        } == [3, 2, 1, 0])
    }

    @Test(arguments: [0.0, 30, 60, 120])
    func aGoneMetroTrainReadsZeroNeverARisingNumber(secondsAfterTheTrain: TimeInterval) {
        #expect(train.countdownMinutes(at: at(secondsLeft: -secondsAfterTheTrain), on: .metro) == 0)
    }

    /// PRIM gives a metro train the same arrival and departure, so "0" of the countdown and "approaching"
    /// (arrival under 60 s) start at the same instant, and the redraw of the approach finds the countdown at 0 already.
    @Test func theZeroOfTheCountdownAndTheApproachOfAMetroTrainStartAtTheSameInstant() throws {
        let departure = Departure(
            line: line4, destination: "Porte de Clignancourt", time: trainTime, arrivalTime: trainTime
        )
        let instants = stride(from: 125.0, through: 1, by: -0.25).map(at(secondsLeft:))

        for now in instants {
            let approaching = PlatformStatus(of: departure, at: now) == .approaching
            let readsZero = train.countdownMinutes(at: now, on: .metro) == 0
            #expect(approaching == readsZero, "\(trainTime.timeIntervalSince(now)) s left")
        }
        let approachRedraw = try #require(PlatformStatus.changeDates(arrival: trainTime, departure: trainTime).first)
        #expect(train.countdownMinutes(at: approachRedraw, on: .metro) == 0)
        #expect(train.countdownMinutes(at: approachRedraw.addingTimeInterval(-1), on: .metro) == 1)
    }

    @Test func anRERWaitKeepsItsRoundUpSoItNeverReadsZeroBeforeTheTrainLeaves() {
        let minutes = [2.75, 2.5, 1.9, 1.25, 0.5, 0.01, -0.5].map { minutesLeft in
            train.countdownMinutes(at: at(secondsLeft: minutesLeft * 60), on: .rer)
        }

        #expect(minutes == [3, 3, 2, 2, 1, 1, 1])
        #expect(train.countdownEnd(on: .rer) == trainTime.addingTimeInterval(60))
    }

    @Test func countsTheMinutesOfTwoDigitsThatTheTimerShowsAtEachMode() {
        let minutes = [10.5, 10, 9.99, 9, 8.99].map { minutesLeft in
            let now = at(secondsLeft: minutesLeft * 60)
            return [train.countdownMinutes(at: now, on: .metro), train.countdownMinutes(at: now, on: .rer)]
        }

        #expect(minutes == [[10, 11], [10, 11], [9, 10], [9, 10], [8, 9]])
    }
}
