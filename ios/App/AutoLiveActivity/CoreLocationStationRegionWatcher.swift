import CoreLocation
import os
import TROMECore

@MainActor
final class CoreLocationStationRegionWatcher: StationRegionWatcher {
    private static let monitorName = "TROMEStationRegions"
    private static let monitorNamesOfOlderBuilds = ["RATPStationRegions"]

    var onWake: (@MainActor (_ enteredRegionId: String?, _ lastKnownFix: PositionFix?) async -> Void)?
    var wakeLog: WakeLog?
    var regionLabel: (String) -> String = { $0 }

    private let manager = CLLocationManager()
    private var session: CLServiceSession?
    private var monitorTask: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?
    private var watched: [String: WatchedRegion]?
    private var hasLoggedNoAlways = false
    private var firstStates = RegionFirstStates()
    private var firstStatesFlush: Task<Void, Never>?

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
        let added = regions.filter { previous[$0.id] != $0 }
        expectFirstStates(of: Set(added.map(\.id)))
        for region in added {
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
        guard manager.authorizationStatus == .authorizedAlways else {
            recordNoAlways()
            return nil
        }
        Self.logAvailability()
        session = CLServiceSession(authorization: .always)
        let task = Task {
            await Self.removeConditionsOfOlderBuilds()
            return await CLMonitor(Self.monitorName)
        }
        monitorTask = task
        let monitor = await task.value
        listen(to: monitor)
        await recordStart(of: monitor)
        return monitor
    }

    private static func removeConditionsOfOlderBuilds() async {
        for name in monitorNamesOfOlderBuilds {
            let monitor = await CLMonitor(name)
            let identifiers = await monitor.identifiers
            for id in identifiers {
                await monitor.remove(id)
            }
            logRemoved(identifiers.count, of: name)
        }
    }

    private func listen(to monitor: CLMonitor) {
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    Self.log(event)
                    self?.record(event)
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
    private func recordNoAlways() {
        #if DEBUG
        guard !hasLoggedNoAlways else { return }
        hasLoggedNoAlways = true
        wakeLog?.record(.system, "Regions not watched: location is not Always")
        #endif
    }

    private func recordStart(of monitor: CLMonitor) async {
        #if DEBUG
        guard let wakeLog else { return }
        let count = await monitor.identifiers.count
        wakeLog.record(.system, "Region watch on: iOS keeps \(count) regions for the app")
        #endif
    }

    private func expectFirstStates(of ids: Set<String>) {
        #if DEBUG
        flushFirstStates()
        firstStates = RegionFirstStates(expecting: ids)
        firstStatesFlush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.flushFirstStates()
        }
        #endif
    }

    private func flushFirstStates() {
        #if DEBUG
        firstStatesFlush?.cancel()
        firstStatesFlush = nil
        if let summary = firstStates.summary {
            wakeLog?.record(.system, summary)
        }
        firstStates = RegionFirstStates()
        #endif
    }

    private func record(_ event: CLMonitor.Event) {
        #if DEBUG
        guard let wakeLog else { return }
        let region = regionLabel(event.identifier)
        let problems = Self.diagnostics(of: event)
        let state = Self.firstState(of: event)
        if firstStates.take(id: event.identifier, label: region, state: state, problems: problems) {
            if firstStates.isComplete {
                flushFirstStates()
            }
            return
        }
        let what = Self.line(of: event, region: region)
        wakeLog.record(.system, problems.isEmpty ? what : "\(what) [\(problems)]")
        #endif
    }

    nonisolated private static func firstState(of event: CLMonitor.Event) -> RegionFirstStates.State {
        switch event.state {
        case .satisfied: .inside
        case .unsatisfied: .outside
        case .unmonitored: .notWatched
        default: .unknown
        }
    }

    nonisolated private static func line(of event: CLMonitor.Event, region: String) -> String {
        switch event.state {
        case .satisfied: "iOS: entered \(region)"
        case .unsatisfied: "iOS: left \(region)"
        case .unknown: "iOS: \(region) is unknown"
        case .unmonitored: "iOS: \(region) is not watched"
        @unknown default: "iOS: \(region), state \(event.state.rawValue)"
        }
    }

    nonisolated private static let logger = Logger(category: "StationRegions")

    nonisolated private static func logAvailability() {
        #if DEBUG
        let available = CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        logger.notice("region monitoring available: \(available, privacy: .public)")
        #endif
    }

    nonisolated private static func logRemoved(_ count: Int, of monitorName: String) {
        #if DEBUG
        guard count > 0 else { return }
        logger.notice("""
            removed \(count, privacy: .public) regions of the monitor \(monitorName, privacy: .public) \
            of an older build
            """)
        #endif
    }

    nonisolated private static func diagnostics(of event: CLMonitor.Event) -> String {
        [
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
    }

    nonisolated private static func log(_ event: CLMonitor.Event) {
        #if DEBUG
        let problems = diagnostics(of: event)
        let state = switch event.state {
        case .unknown: "unknown"
        case .satisfied: "satisfied"
        case .unsatisfied: "unsatisfied"
        case .unmonitored: "unmonitored"
        @unknown default: "raw value \(event.state.rawValue)"
        }
        logger.notice("""
            \(event.identifier, privacy: .public): state \(state, privacy: .public), \
            diagnostics [\(problems, privacy: .public)]
            """)
        #endif
    }
}
