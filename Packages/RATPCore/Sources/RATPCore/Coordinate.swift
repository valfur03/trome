import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    private static let earthRadiusMeters = 6_371_000.0

    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public func distance(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLatitude = lat2 - lat1
        let deltaLongitude = (other.longitude - longitude) * .pi / 180
        let haversine = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * Self.earthRadiusMeters * asin(min(1, sqrt(haversine)))
    }
}
