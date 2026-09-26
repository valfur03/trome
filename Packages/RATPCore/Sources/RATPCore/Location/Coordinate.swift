import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    private static let earthRadiusMeters = 6_371_000.0

    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    public init?(parsing text: String) {
        let parts = text
            .split { $0 == "," || $0 == ";" || $0.isWhitespace }
            .map(String.init)
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else {
            return nil
        }
        self.init(latitude: latitude, longitude: longitude)
    }

    init(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var formatted: String {
        String(format: "%.5f, %.5f", latitude, longitude)
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
