import Foundation

/// A stop of the station that did not answer while another one did.
/// The app does not know the trains of its directions, so it must not say "no train" there:
/// it keeps the times of an earlier answer while their first train has not left, else it shows an empty box.
extension DepartureBoard {
    func hasNoAnswer(for line: TransitLine) -> Bool {
        !unansweredStops.isDisjoint(with: PRIMStopReference.monitoringRefs(of: line))
    }

    func earlierDepartures(of line: TransitLine) -> [Departure] {
        earlierDepartures.filter { $0.line.mode == line.mode && $0.line.name == line.name }
    }

    /// The trains to keep for the stops that did not answer this time, taken from the board of the last answer:
    /// the trains that it got from these stops and that have not left yet, or, for a stop that did not answer
    /// then either, the trains that it kept itself.
    func departuresToKeep(forUnanswered stops: Set<String>, now: Date) -> [Departure] {
        let answeredThen = stops.subtracting(unansweredStops)
        let stillUnanswered = stops.intersection(unansweredStops)
        let fresh = (departures + laterDepartures).filter { departure in
            departure.time > now && Self.departure(departure, isFromOneOf: answeredThen)
        }
        let kept = earlierDepartures.filter { Self.departure($0, isFromOneOf: stillUnanswered) }
        return fresh + kept
    }

    static func departure(_ departure: Departure, isFromOneOf stops: Set<String>) -> Bool {
        PRIMStopReference.monitoringRefs(of: departure.line).contains { stop in
            stops.contains(stop) && (!PRIMStopReference.isQuay(stop) || departure.quayRef == stop)
        }
    }
}
