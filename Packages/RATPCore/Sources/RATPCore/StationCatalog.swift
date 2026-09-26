import Foundation

public struct StationCatalog: Sendable {
    public static let walkingDistanceMeters = 2_000.0

    public let stations: [Station]

    public init(stations: [Station]) {
        self.stations = stations
    }

    public init(jsonData: Data) throws {
        self.init(stations: try JSONDecoder().decode([Station].self, from: jsonData))
    }

    public static func bundled() throws -> StationCatalog {
        guard let url = Bundle.module.url(forResource: "stations", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try StationCatalog(jsonData: Data(contentsOf: url))
    }

    public func nearestStation(
        to coordinate: Coordinate,
        within maximumDistanceMeters: Double = walkingDistanceMeters
    ) -> NearbyStation? {
        stations
            .map { NearbyStation(station: $0, distanceMeters: coordinate.distance(to: $0.coordinate)) }
            .filter { $0.distanceMeters <= maximumDistanceMeters }
            .min { $0.distanceMeters < $1.distanceMeters }
    }
}
