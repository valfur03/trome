import Foundation

public enum TransitMode: String, Codable, Hashable, Sendable {
    case metro
    case rer
}

public struct TransitLine: Codable, Hashable, Sendable {
    public var mode: TransitMode
    public var name: String
    public var stopIds: [String]
    public var stopAreaIds: [String]

    public init(mode: TransitMode, name: String, stopIds: [String] = [], stopAreaIds: [String] = []) {
        self.mode = mode
        self.name = name
        self.stopIds = stopIds
        self.stopAreaIds = stopAreaIds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(TransitMode.self, forKey: .mode)
        name = try container.decode(String.self, forKey: .name)
        stopIds = try container.decode([String].self, forKey: .stopIds)
        stopAreaIds = try container.decodeIfPresent([String].self, forKey: .stopAreaIds) ?? []
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
    public var hubId: String?

    public init(id: String, name: String, coordinate: Coordinate, lines: [TransitLine], hubId: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.lines = lines
        self.hubId = hubId
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
