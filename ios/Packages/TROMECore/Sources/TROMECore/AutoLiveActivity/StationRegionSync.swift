import Foundation

/// Gives iOS the areas of the last plan, one plan at a time.
///
/// Each plan compares itself with the areas that iOS keeps, not with the last plan:
/// a plan that comes while another one is still adding its areas would otherwise leave areas in iOS
/// that no later plan removes, and iOS refuses new areas past its limit.
@MainActor
public final class StationRegionSync {
    public var onAdding: (Set<String>) -> Void = { _ in }
    public var wakeLog: WakeLog?

    private let monitor: any RegionMonitor
    private var added: [String: WatchedRegion] = [:]
    private var pending: [WatchedRegion]?
    private var run: Task<Void, Never>?

    public init(monitor: any RegionMonitor) {
        self.monitor = monitor
    }

    /// Returns once iOS has the areas of this plan, or of a later plan that replaced it.
    public func watch(_ regions: [WatchedRegion]) async {
        pending = regions
        let run = self.run ?? startRun()
        await run.value
    }

    private func startRun() -> Task<Void, Never> {
        let run = Task {
            while let plan = pending {
                pending = nil
                await apply(plan)
            }
            self.run = nil
        }
        self.run = run
        return run
    }

    private func apply(_ regions: [WatchedRegion]) async {
        let planned = Dictionary(regions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(await monitor.identifiers)
        for id in kept where planned[id] == nil {
            await monitor.remove(id)
            added[id] = nil
        }
        let toAdd = regions.filter { !kept.contains($0.id) || added[$0.id] != $0 }
        onAdding(Set(toAdd.map(\.id)))
        for region in toAdd {
            await monitor.add(region)
            added[region.id] = region
        }
        await recordCount(planned: planned.count)
    }

    private func recordCount(planned: Int) async {
        guard let wakeLog else { return }
        let count = await monitor.identifiers.count
        guard count != planned else { return }
        wakeLog.record(.system, "iOS keeps \(count) areas for the app, the plan has \(planned)")
    }
}
