import CoreLocation
import RATPCore

@MainActor
final class CoreLocationStationRegionWatcher: StationRegionWatcher {
    private static let monitorName = "RATPStationRegions"
    private static let freshLocationAge: TimeInterval = 120

    var onWake: (@MainActor (Coordinate) async -> Void)?

    private let catalog: StationCatalog
    private let manager = CLLocationManager()
    private var session: CLServiceSession?
    private var monitorTask: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?
    private var watched: [String: WatchedRegion]?

    init(catalog: StationCatalog) {
        self.catalog = catalog
    }

    func resume() async {
        _ = await startedMonitor()
    }

    func watch(_ regions: [WatchedRegion]) async {
        guard let monitor = await startedMonitor() else { return }
        let previous = watched ?? [:]
        let existingIds: Set<String>
        if let watched {
            existingIds = Set(watched.keys)
        } else {
            existingIds = Set(await monitor.identifiers)
        }
        let newIds = Set(regions.map(\.id))
        watched = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })
        for id in existingIds.subtracting(newIds) {
            await monitor.remove(id)
        }
        for region in regions where previous[region.id] != region {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                radius: region.radiusMeters
            )
            await monitor.add(condition, identifier: region.id, assuming: .unsatisfied)
        }
    }

    private func startedMonitor() async -> CLMonitor? {
        if let monitorTask {
            return await monitorTask.value
        }
        guard manager.authorizationStatus == .authorizedAlways else { return nil }
        session = CLServiceSession(authorization: .always)
        let task = Task { await CLMonitor(Self.monitorName) }
        monitorTask = task
        let monitor = await task.value
        listen(to: monitor)
        return monitor
    }

    private func listen(to monitor: CLMonitor) {
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    await self?.handle(identifier: event.identifier, state: event.state)
                }
            } catch {
                return
            }
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) async {
        guard state == .satisfied || state == .unsatisfied else { return }
        let position = WatchedRegion.position(
            afterEnteringRegionId: state == .satisfied ? identifier : nil,
            lastKnownPosition: freshLocation(),
            catalog: catalog
        )
        guard let position else { return }
        await onWake?(position)
    }

    private func freshLocation() -> Coordinate? {
        guard let location = manager.location,
              -location.timestamp.timeIntervalSinceNow < Self.freshLocationAge else {
            return nil
        }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

@MainActor
final class BackgroundActivityLocationKeeper: BackgroundLocationKeeper {
    private var session: CLBackgroundActivitySession?

    func begin() {
        guard session == nil else { return }
        session = CLBackgroundActivitySession()
    }

    func end() {
        session?.invalidate()
        session = nil
    }
}
