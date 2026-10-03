import Foundation

public struct DepartureGroup: Hashable, Identifiable, Sendable {
    public var line: TransitLine
    public var destination: String
    public var times: [Date]
    public var stationName: String?
    public var nextTrainIsOverAnHourAway: Bool

    public init(
        line: TransitLine,
        destination: String,
        times: [Date],
        stationName: String? = nil,
        nextTrainIsOverAnHourAway: Bool = false
    ) {
        self.line = line
        self.destination = destination
        self.times = times
        self.stationName = stationName
        self.nextTrainIsOverAnHourAway = nextTrainIsOverAnHourAway
    }

    public var id: String {
        "\(line.mode.rawValue)-\(line.name)-\(destination)"
    }

    public func upcomingTimes(after now: Date) -> [Date] {
        times.filter { $0 > now.addingTimeInterval(-DepartureBoard.departedGraceSeconds) }
    }

    public func isShown(at now: Date) -> Bool {
        nextTrainIsOverAnHourAway || !upcomingTimes(after: now).isEmpty
    }
}
