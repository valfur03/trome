import CoreLocation
import os
import TROMECore
import UIKit

@MainActor
final class CoreLocationStationRegionWatcher: StationRegionWatcher {
    private static let monitorName = "TROMEStationRegions"
    private static let monitorNamesOfOlderBuilds = ["RATPStationRegions"]

    var onWake: (@MainActor (_ event: RegionEvent, _ lastKnownFix: PositionFix?) async -> Void)?
    var wakeLog: WakeLog?
    var catalog: StationCatalog?

    private let manager = CLLocationManager()
    private var session: CLServiceSession?
    private var monitorTask: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?
    private var sync: StationRegionSync?
    private var hasLoggedNoAlways = false
    private var firstStates = RegionFirstStates()
    private var firstStatesFlush: Task<Void, Never>?

    func resume() async {
        _ = await startedMonitor()
    }

    func watch(_ regions: [WatchedRegion]) async {
        guard let monitor = await startedMonitor() else { return }
        let sync = self.sync ?? makeSync(of: monitor)
        await sync.watch(regions)
    }

    private func makeSync(of monitor: CLMonitor) -> StationRegionSync {
        let sync = StationRegionSync(monitor: CoreLocationRegionMonitor(monitor))
        sync.wakeLog = wakeLog
        sync.onAddingNew = { [weak self] ids in self?.expectFirstStates(of: ids) }
        self.sync = sync
        return sync
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
                    let lastKnownFix = self?.manager.location.flatMap(PositionFix.init)
                    let regionEvent = Self.regionEvent(of: event)
                    Self.log(event)
                    self?.record(event, as: regionEvent, phoneAt: lastKnownFix)
                    if let regionEvent {
                        await self?.handle(regionEvent, lastKnownFix: lastKnownFix)
                    }
                }
            } catch {
                return
            }
        }
    }

    nonisolated private static func regionEvent(of event: CLMonitor.Event) -> RegionEvent? {
        switch event.state {
        case .satisfied: .entered(regionId: event.identifier)
        case .unsatisfied: .left(regionId: event.identifier)
        default: nil
        }
    }

    private func handle(_ event: RegionEvent, lastKnownFix: PositionFix?) async {
        let wakeTime = RegionWakeTime()
        await onWake?(event, lastKnownFix)
        wakeTime.end()
    }
}

/// Asks iOS for time to finish a region wake: on a report of arrival, the app may wait several seconds
/// for a position, and iOS suspends an app soon after it wakes it.
@MainActor
private final class RegionWakeTime {
    private var task = UIBackgroundTaskIdentifier.invalid

    init() {
        task = UIApplication.shared.beginBackgroundTask(withName: "Region wake") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
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

    /// Writes the event before the app decides on it, with the position that the app decides on,
    /// so that a wake says where the phone was even when the app then decides nothing.
    private func record(_ event: CLMonitor.Event, as regionEvent: RegionEvent?, phoneAt fix: PositionFix?) {
        #if DEBUG
        guard let wakeLog, let catalog else { return }
        let now = Date()
        let region = regionEvent == nil
            ? WatchedRegion.label(ofId: event.identifier, catalog: catalog)
            : WatchedRegion.wakeLabel(ofId: event.identifier, phoneAt: fix, now: now, catalog: catalog)
        let problems = Self.diagnostics(of: event)
        let state = Self.firstState(of: event)
        if state == .inside,
           let line = regionEvent?.firstStateLine(phoneAt: fix, now: now, catalog: catalog),
           firstStates.release(id: event.identifier) {
            wakeLog.record(.system, problems.isEmpty ? line : "\(line) [\(problems)]")
            if firstStates.isComplete {
                flushFirstStates()
            }
            return
        }
        if firstStates.take(id: event.identifier, label: region, state: state, problems: problems) {
            if firstStates.isComplete {
                flushFirstStates()
            }
            return
        }
        let what = regionEvent?.wakeLine(phoneAt: fix, now: now, catalog: catalog)
            ?? Self.line(of: event, region: region)
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
        case .unknown: "iOS: \(region) is unknown"
        case .unmonitored: "iOS: \(region) is not watched"
        default: "iOS: \(region), state \(event.state.rawValue)"
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
