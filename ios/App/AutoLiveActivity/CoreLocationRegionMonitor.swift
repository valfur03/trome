import CoreLocation
import TROMECore

/// The areas of a `CLMonitor`, for `StationRegionSync`.
@MainActor
final class CoreLocationRegionMonitor: RegionMonitor {
    private let monitor: CLMonitor

    init(_ monitor: CLMonitor) {
        self.monitor = monitor
    }

    var identifiers: [String] {
        get async { await monitor.identifiers }
    }

    func add(_ region: WatchedRegion) async {
        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
            radius: region.radiusMeters
        )
        let assumed: CLMonitor.Event.State = region.startsInside ? .satisfied : .unsatisfied
        await monitor.add(condition, identifier: region.id, assuming: assumed)
    }

    func remove(_ id: String) async {
        await monitor.remove(id)
    }
}
