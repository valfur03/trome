import Foundation

public enum TransitMode: String, Codable, Hashable, Sendable {
    case metro
    case rer
}

public struct TransitLine: Codable, Hashable, Sendable {
    public var mode: TransitMode
    public var name: String
    public var stopIds: [String]

    public init(mode: TransitMode, name: String, stopIds: [String] = []) {
        self.mode = mode
        self.name = name
        self.stopIds = stopIds
    }

    public var displayName: String {
        switch mode {
        case .metro: "Metro \(name)"
        case .rer: "RER \(name)"
        }
    }
}

public struct Station: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var lines: [TransitLine]

    public init(id: String, name: String, coordinate: Coordinate, lines: [TransitLine]) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.lines = lines
    }

    public var coordinate: Coordinate {
        Coordinate(latitude, longitude)
    }
}

public struct NearbyStation: Hashable, Sendable {
    public var station: Station
    public var distanceMeters: Double

    public init(station: Station, distanceMeters: Double) {
        self.station = station
        self.distanceMeters = distanceMeters
    }
}
