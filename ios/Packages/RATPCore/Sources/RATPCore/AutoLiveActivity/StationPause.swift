import Foundation

public struct StationPause: Codable, Equatable, Sendable {
    public static let duration: TimeInterval = 60 * 60

    public var stationId: String
    public var end: Date

    public init(stationId: String, end: Date) {
        self.stationId = stationId
        self.end = end
    }

    func pauses(_ stationId: String, at now: Date) -> Bool {
        self.stationId == stationId && isActive(at: now)
    }

    func isActive(at now: Date) -> Bool {
        now < end
    }
}

public struct PausedStation: Equatable, Sendable {
    public let station: Station
    public let end: Date
}
