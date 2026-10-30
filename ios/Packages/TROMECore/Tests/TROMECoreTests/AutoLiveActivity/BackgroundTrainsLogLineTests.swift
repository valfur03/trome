import Foundation
import Testing
@testable import TROMECore

/// The Wake log line of a background call tells the next outing whether the app asked, what answered, how old
/// the answer was, and what it handed to iOS: the minutes of the lock screen once stood still for 4 minutes,
/// and no log could tell why.
struct BackgroundTrainsLogLineTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let lineA = TransitLine(mode: .rer, name: "A")
    private var station: Station {
        Station(id: "parc", name: "Le Parc de Saint-Maur", coordinate: Coordinate(48.8, 2.5), lines: [lineA])
    }

    private func date(_ time: String) -> Date {
        ISO8601DateFormatter().date(from: "2026-10-18T\(time)Z")!
    }

    private func answer(at answeredAt: Date, _ trains: [(String, String)]) -> NextTrainsState {
        let departures = trains.map { Departure(line: lineA, destination: $0.0, time: date($0.1)) }
        return .departures(DepartureBoard(departures: departures, stations: [station], now: answeredAt), updatedAt: answeredAt)
    }

    @Test func givesTheAgeOfTheAnswerTheNextTrainOfEachDirectionAndTheNextAsk() {
        let state = answer(at: date("15:01:48"), [
            ("Saint-Germain-en-Laye", "15:05:10"), ("Saint-Germain-en-Laye", "15:11:00"),
            ("Boissy-Saint-Léger", "15:06:02")
        ])

        let line = BackgroundTrainsLogLine.text(
            station: station, state: state, now: date("15:02:00"), nextCall: date("15:04:00"), timeZone: utc
        )

        #expect(line.hasPrefix("Asked for Le Parc de Saint-Maur: answer 12 s old, "))
        #expect(line.contains("A Saint-Germain-en-Laye 15:05:10"))
        #expect(line.contains("A Boissy-Saint-Léger 15:06:02"))
        #expect(!line.contains("15:11:00"))
        #expect(line.hasSuffix("; next ask by 15:04:00"))
    }

    @Test func showsAnAnswerFourMinutesOldAsSuch() {
        let state = answer(at: date("15:00:00"), [("Boissy-Saint-Léger", "15:06:02")])

        let line = BackgroundTrainsLogLine.text(
            station: station, state: state, now: date("15:04:00"), nextCall: date("15:06:00"), timeZone: utc
        )

        #expect(line.contains("answer 240 s old"))
    }

    @Test func namesTheFailureOfACallThatGotNoAnswer() {
        let line = BackgroundTrainsLogLine.text(
            station: station, state: .failed(.unreachable), now: date("15:02:00"), nextCall: date("15:04:00"),
            timeZone: utc
        )

        #expect(line == "Asked for Le Parc de Saint-Maur: no answer (unreachable); next ask by 15:04:00")
    }

    @Test func saysWhenTheAppAsksNoMore() {
        let line = BackgroundTrainsLogLine.text(
            station: station, state: .failed(.appTokenRefused), now: date("15:02:00"), nextCall: nil, timeZone: utc
        )

        #expect(line == "Asked for Le Parc de Saint-Maur: no answer (appTokenRefused); asks no more")
    }

    @Test func keepsTheLineShortAtABigStation() {
        let destinations = (1...6).map { ("End \($0)", "15:0\($0):00") }
        let state = answer(at: date("15:00:00"), destinations)

        let line = BackgroundTrainsLogLine.text(
            station: station, state: state, now: date("15:00:00"), nextCall: date("15:02:00"), timeZone: utc
        )

        #expect(line.contains("A End 4 15:04:00, +2 more;"))
        #expect(!line.contains("End 5"))
    }
}
