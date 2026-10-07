import Foundation

struct ExampleTimetable: Sendable {
    static let stationId = "IDFM:21959"
    static let trainsPerSide = 4
    static let platformSeconds: TimeInterval = 30
    /// No train of the hub leaves before this time after the tap.
    /// iOS suspends the app soon after the lock, and with no server nothing updates the Live Activity:
    /// it goes stale when its soonest train leaves.
    /// So the lock screen counts down for 5 minutes, and a train of the first page is in its last minute from 4:20.
    static let firstDepartureSeconds: TimeInterval = 5 * 60 + 20

    let start: Date

    func trains(at stations: [Station], now: Date) -> NextTrainsState {
        let board = DepartureBoard(departures: departures(at: stations, now: now), stations: stations, now: now)
        return .departures(board, updatedAt: now)
    }

    func departures(at stations: [Station], now: Date) -> [Departure] {
        let lines = stations.flatMap { station in station.lines.map { (station: station, line: $0) } }
        return lines.enumerated().flatMap { lineIndex, served in
            served.line.departureSides(at: served.station).flatMap { side in
                let interval = Self.minutesBetweenTrains(of: served.line, index: lineIndex) * 60
                return departures(
                    of: served.line,
                    every: interval,
                    firstAfter: Self.firstTrainDelay(lineIndex: lineIndex, sideIndex: side.index, interval: interval),
                    toward: side.destinations,
                    now: now
                )
            }
        }
    }

    private func departures(
        of line: TransitLine,
        every interval: TimeInterval,
        firstAfter firstDelay: TimeInterval,
        toward destinations: [String],
        now: Date
    ) -> [Departure] {
        let sinceFirst = now.timeIntervalSince(start) - firstDelay
        let firstShown = sinceFirst < 0 ? 0 : Int((sinceFirst / interval).rounded(.down)) + 1
        return (firstShown..<firstShown + Self.trainsPerSide).map { index in
            let time = start.addingTimeInterval(firstDelay + Double(index) * interval)
            return Departure(
                line: line,
                destination: destinations[index % destinations.count],
                time: time,
                arrivalTime: time.addingTimeInterval(-Self.platformSeconds)
            )
        }
    }

    private static func minutesBetweenTrains(of line: TransitLine, index: Int) -> TimeInterval {
        TimeInterval((line.mode == .metro ? 3 : 5) + index % 3)
    }

    private static func firstTrainDelay(lineIndex: Int, sideIndex: Int, interval: TimeInterval) -> TimeInterval {
        firstDepartureSeconds + TimeInterval(lineIndex * 67 + sideIndex * 101).truncatingRemainder(dividingBy: interval)
    }
}
