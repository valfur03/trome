import Foundation

public struct DepartureBoard: Hashable, Sendable {
    public static let departedGraceSeconds: TimeInterval = 30
    public static let timesPerGroup = 3
    static let farthestTimeSeconds: TimeInterval = 60 * 60

    public let groups: [DepartureGroup]
    public let departures: [Departure]
    public let stations: [Station]
    public let lines: [TransitLine]

    public init(departures: [Departure], stations: [Station], now: Date) {
        let lines = stations.flatMap(\.lines).sorted(by: TransitLine.stationListOrder)
        self.stations = stations
        self.lines = lines
        let upcoming = departures
            .filter { $0.time > now.addingTimeInterval(-Self.departedGraceSeconds) }
            .filter { $0.time <= now.addingTimeInterval(Self.farthestTimeSeconds) }
            .sorted { $0.time < $1.time }
        self.departures = upcoming
        var groups: [DepartureGroup] = []
        for departure in upcoming {
            if let index = groups.firstIndex(where: {
                $0.line == departure.line && $0.destination == departure.destination
            }) {
                if groups[index].times.count < Self.timesPerGroup {
                    groups[index].times.append(departure.time)
                }
            } else {
                groups.append(
                    DepartureGroup(line: departure.line, destination: departure.destination, times: [departure.time])
                )
            }
        }
        self.groups = groups.sorted { first, second in
            let firstLine = lines.firstIndex(of: first.line) ?? lines.count
            let secondLine = lines.firstIndex(of: second.line) ?? lines.count
            if firstLine != secondLine {
                return firstLine < secondLine
            }
            return first.destination.localizedStandardCompare(second.destination) == .orderedAscending
        }
    }

    public var isEmpty: Bool {
        groups.isEmpty
    }

    func station(serving line: TransitLine) -> Station? {
        stations.first { $0.lines.contains(line) }
    }
}
