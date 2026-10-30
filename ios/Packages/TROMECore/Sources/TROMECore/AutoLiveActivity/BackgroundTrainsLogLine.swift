import Foundation

/// The Wake log line of a call that the app makes for its Live Activity in the background (debug builds only).
/// It says what answered, how old the answer was, the next train of each direction that the app handed to iOS,
/// and when the app means to ask again.
/// Why: on a walk, the minutes of the lock screen stood still for 4 minutes, and no log could tell whether the
/// app asked, what answered, or what it drew. With this line, a gap after "next ask by" means that iOS did not
/// run the app; an old answer or a failure is written; and new times here under old times on the lock screen
/// mean that the draw failed.
enum BackgroundTrainsLogLine {
    static let maximumDirections = 4

    static func text(
        station: Station,
        state: NextTrainsState,
        now: Date,
        nextCall: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        let clock = Clock(timeZone: timeZone)
        let next = nextCall.map { "next ask by \(clock.time($0))" } ?? "asks no more"
        return "Asked for \(station.name): \(answer(state, now: now, clock: clock)); \(next)"
    }

    private static func answer(_ state: NextTrainsState, now: Date, clock: Clock) -> String {
        switch state {
        case .departures(let board, let updatedAt):
            let age = Int(now.timeIntervalSince(updatedAt).rounded())
            let directions = board.groups.prefix(maximumDirections).map { group in
                let first = group.times.first.map(clock.time) ?? "none"
                return "\(group.line.name) \(group.destination) \(first)"
            }
            let more = board.groups.count > maximumDirections ? ", +\(board.groups.count - maximumDirections) more" : ""
            return "answer \(age) s old, " + directions.joined(separator: ", ") + more
        case .noLiveData:
            return "answer with no train"
        case .failed(let error):
            return "no answer (\(error))"
        case .idle, .missingKey, .loading:
            return "no answer (\(state))"
        }
    }

    private struct Clock {
        let formatter: DateFormatter

        init(timeZone: TimeZone) {
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm:ss"
        }

        func time(_ date: Date) -> String {
            formatter.string(from: date)
        }
    }
}
