import Foundation

public struct WatchedRegion: Hashable, Sendable {
    static let arrivalPrefix = "arrival:"
    static let stopPrefix = "stop:"
    static let refreshId = "refresh"

    public let id: String
    public let center: Coordinate
    public let radiusMeters: Double
    /// The state that iOS assumes for the region until it knows better, also when a new process adds it again.
    /// A stop area is planned only while the rider is at its station, so it starts inside: only a real exit
    /// then reports "left". Assumed outside, an echo of that assumption would forget an arrival that the rider
    /// is still at (and the next "entered" would notify again), and a re-add would swallow a real exit.
    public let startsInside: Bool

    init(id: String, center: Coordinate, radiusMeters: Double, startsInside: Bool = false) {
        self.id = id
        self.center = center
        self.radiusMeters = radiusMeters
        self.startsInside = startsInside
    }

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
            radiusMeters: AutoLiveActivityRules.stopRadiusMeters,
            startsInside: true
        )
    }

    static func refresh(around position: Coordinate, radiusMeters: Double) -> WatchedRegion {
        WatchedRegion(id: refreshId, center: position, radiusMeters: radiusMeters)
    }

    public static func arrivalStationId(inRegionId id: String) -> String? {
        guard id.hasPrefix(arrivalPrefix) else { return nil }
        return String(id.dropFirst(arrivalPrefix.count))
    }

    /// The position to decide a wake on, other than a report of arrival (`ReportedArrivalRules`): the last one,
    /// when it is at most 2 minutes old.
    static func recentFix(_ lastKnownFix: PositionFix?, now: Date) -> PositionFix? {
        lastKnownFix.flatMap {
            now.timeIntervalSince($0.timestamp) <= AutoLiveActivityRules.maximumMonitoredPositionAge ? $0 : nil
        }
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
