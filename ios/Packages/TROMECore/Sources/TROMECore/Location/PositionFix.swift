import Foundation

public struct PositionFix: Equatable, Sendable {
    public let coordinate: Coordinate
    public let accuracyMeters: Double
    public let timestamp: Date

    public init(coordinate: Coordinate, accuracyMeters: Double, timestamp: Date) {
        self.coordinate = coordinate
        self.accuracyMeters = accuracyMeters
        self.timestamp = timestamp
    }

    static func exact(_ coordinate: Coordinate) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: 0, timestamp: Date())
    }
}
