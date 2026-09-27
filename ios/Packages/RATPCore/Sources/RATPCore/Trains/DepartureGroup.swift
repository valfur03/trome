import Foundation

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
