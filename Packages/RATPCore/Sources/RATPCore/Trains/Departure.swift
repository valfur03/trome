import Foundation

public struct Departure: Hashable, Sendable {
    public var line: TransitLine
    public var destination: String
    public var time: Date

    public init(line: TransitLine, destination: String, time: Date) {
        self.line = line
        self.destination = destination
        self.time = time
    }
}

public struct DepartureGroup: Hashable, Identifiable, Sendable {
    public var line: TransitLine
    public var destination: String
    public var times: [Date]

    public init(line: TransitLine, destination: String, times: [Date]) {
        self.line = line
        self.destination = destination
        self.times = times
    }

    public var id: String {
        "\(line.mode.rawValue)-\(line.name)-\(destination)"
    }

    public func upcomingTimes(after now: Date) -> [Date] {
        times.filter { $0 > now.addingTimeInterval(-DepartureBoard.departedGraceSeconds) }
    }
}

public struct DepartureBoard: Hashable, Sendable {
    public static let departedGraceSeconds: TimeInterval = 30
    public static let timesPerGroup = 3

    public let groups: [DepartureGroup]

    public init(groups: [DepartureGroup]) {
        self.groups = groups
    }

    public init(departures: [Departure], lines: [TransitLine], now: Date) {
        let upcoming = departures
            .filter { $0.time > now.addingTimeInterval(-Self.departedGraceSeconds) }
            .sorted { $0.time < $1.time }
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
}

public enum DepartureTime {
    public static func minutes(until time: Date, from now: Date) -> Int {
        max(0, Int((time.timeIntervalSince(now) / 60).rounded(.down)))
    }
}
