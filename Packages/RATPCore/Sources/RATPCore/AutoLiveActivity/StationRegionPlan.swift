import Foundation

public struct WatchedRegion: Hashable, Sendable {
    private static let arrivalPrefix = "arrival:"
    private static let stopPrefix = "stop:"
    private static let refreshId = "refresh"

    public let id: String
    public let center: Coordinate
    public let radiusMeters: Double

    static func arrival(at station: Station) -> WatchedRegion {
        WatchedRegion(
            id: arrivalPrefix + station.id,
            center: station.coordinate,
            radiusMeters: AutoLiveActivityRules.arrivalRadiusMeters
        )
    }

    static func stop(around station: Station) -> WatchedRegion {
        WatchedRegion(
            id: stopPrefix + station.id,
            center: station.coordinate,
            radiusMeters: AutoLiveActivityRules.stopRadiusMeters
        )
    }

    static func refresh(around position: Coordinate, radiusMeters: Double) -> WatchedRegion {
        WatchedRegion(id: refreshId, center: position, radiusMeters: radiusMeters)
    }

    public static func arrivalStationId(inRegionId id: String) -> String? {
        guard id.hasPrefix(arrivalPrefix) else { return nil }
        return String(id.dropFirst(arrivalPrefix.count))
    }
}

public enum StationRegionPlan {
    public static let maximumRegions = 20
    public static let minimumRefreshRadiusMeters = 200.0
    public static let replanDistanceMeters = 100.0

    public static func regions(
        around position: Coordinate,
        stopStation: Station?,
        catalog: StationCatalog
    ) -> [WatchedRegion] {
        let arrivalCount = maximumRegions - 2
        let nearest = catalog.stations
            .map { (station: $0, distance: position.distance(to: $0.coordinate)) }
            .sorted { $0.distance < $1.distance }
            .prefix(arrivalCount)
        let farthest = nearest.last?.distance ?? 0
        let refreshRadius = max(
            minimumRefreshRadiusMeters,
            farthest - AutoLiveActivityRules.arrivalRadiusMeters
        )
        var regions = nearest.map { WatchedRegion.arrival(at: $0.station) }
        if let stopStation {
            regions.append(.stop(around: stopStation))
        }
        regions.append(.refresh(around: position, radiusMeters: refreshRadius))
        return regions
    }
}
