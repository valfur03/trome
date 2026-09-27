import Foundation

public struct DepartureGroup: Hashable, Identifiable, Sendable {
    public var line: TransitLine
    public var destination: String
    public var times: [Date]
    public var stationName: String?

    public init(line: TransitLine, destination: String, times: [Date], stationName: String? = nil) {
        self.line = line
        self.destination = destination
        self.times = times
        self.stationName = stationName
    }

    public var id: String {
        "\(line.mode.rawValue)-\(line.name)-\(destination)"
    }

    public func upcomingTimes(after now: Date) -> [Date] {
        times.filter { $0 > now.addingTimeInterval(-DepartureBoard.departedGraceSeconds) }
    }
}
