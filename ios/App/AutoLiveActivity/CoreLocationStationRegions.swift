import CoreLocation
import os
import RATPCore

@MainActor
final class CoreLocationStationRegionWatcher: StationRegionWatcher {
    private static let monitorName = "RATPStationRegions"

    var onWake: (@MainActor (_ enteredRegionId: String?, _ lastKnownFix: PositionFix?) async -> Void)?

    private let manager = CLLocationManager()
    private var session: CLServiceSession?
    private var monitorTask: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?
    private var watched: [String: WatchedRegion]?

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
        Self.logAvailability()
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
                    Self.log(event)
                    await self?.handle(identifier: event.identifier, state: event.state)
                }
            } catch {
                return
            }
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) async {
        guard state == .satisfied || state == .unsatisfied else { return }
        await onWake?(state == .satisfied ? identifier : nil, manager.location.flatMap(PositionFix.init))
    }
}

extension CoreLocationStationRegionWatcher {
    nonisolated private static let logger = Logger(subsystem: "RATPActivity", category: "StationRegions")

    nonisolated private static func logAvailability() {
        #if DEBUG
        let available = CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        logger.notice("region monitoring available: \(available, privacy: .public)")
        #endif
    }

    nonisolated private static func log(_ event: CLMonitor.Event) {
        #if DEBUG
        let diagnostics = [
            ("authorizationDenied", event.authorizationDenied),
            ("authorizationDeniedGlobally", event.authorizationDeniedGlobally),
            ("authorizationRestricted", event.authorizationRestricted),
            ("insufficientlyInUse", event.insufficientlyInUse),
            ("accuracyLimited", event.accuracyLimited),
            ("conditionUnsupported", event.conditionUnsupported),
            ("conditionLimitExceeded", event.conditionLimitExceeded),
            ("persistenceUnavailable", event.persistenceUnavailable),
            ("serviceSessionRequired", event.serviceSessionRequired),
            ("authorizationRequestInProgress", event.authorizationRequestInProgress)
        ].filter(\.1).map(\.0).joined(separator: ", ")
        let state = switch event.state {
        case .unknown: "unknown"
        case .satisfied: "satisfied"
        case .unsatisfied: "unsatisfied"
        case .unmonitored: "unmonitored"
        @unknown default: "raw value \(event.state.rawValue)"
        }
        logger.notice("""
            \(event.identifier, privacy: .public): state \(state, privacy: .public), \
            diagnostics [\(diagnostics, privacy: .public)]
            """)
        #endif
    }
}
