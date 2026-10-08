import Foundation

extension LineDirections {
    /// The directions of a line of which a stop did not answer while another stop of the station did.
    /// A direction with no train from this answer may have trains that the app does not know, so it never
    /// says "no train": it shows the times of an earlier answer while their first train has not left,
    /// like the times kept after a failed call, else an empty box. A line with no direction at all gets
    /// the directions toward each of its ends, so that the rider still reads where the line goes.
    static func directions(
        of line: TransitLine,
        at station: Station,
        answered: [LineDirection],
        earlier: [Departure],
        now: Date
    ) -> [LineDirection] {
        let kept = directions(of: line, at: station, trainsFrom: earlier, now: now)
            .filter { direction in direction.trains.first.map { $0.time > now } ?? false }
        var shown = answered.isEmpty
            ? directions(of: line, at: station, trainsFrom: [], now: now, showsEverySide: true)
            : answered
        for index in shown.indices where shown[index].trains.isEmpty && !shown[index].nextTrainIsOverAnHourAway {
            if let earlierDirection = kept.first(where: { $0.label == shown[index].label }) {
                shown[index] = earlierDirection
            } else {
                shown[index].noAnswer = true
            }
        }
        for direction in kept where shown.count < maximumDirections
            && !shown.contains(where: { $0.label == direction.label }) {
            shown.append(direction)
        }
        return shown
    }
}
