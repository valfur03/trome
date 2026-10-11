import Foundation
import Testing
@testable import TROMECore

@MainActor
final class FakeRegionMonitor: RegionMonitor {
    private(set) var ids: [String]
    private(set) var mostIds = 0
    /// Areas that iOS keeps even when the app removes them, to see the line of the wake log.
    var stuckIds: Set<String> = []
    private var holdsNextAdd = false
    private var held: CheckedContinuation<Void, Never>?

    init(ids: [String] = []) {
        self.ids = ids
        mostIds = ids.count
    }

    var identifiers: [String] {
        get async { ids }
    }

    var isHoldingAnAdd: Bool {
        held != nil
    }

    func add(_ region: WatchedRegion) async {
        if holdsNextAdd {
            holdsNextAdd = false
            await withCheckedContinuation { held = $0 }
        }
        if !ids.contains(region.id) {
            ids.append(region.id)
        }
        mostIds = max(mostIds, ids.count)
    }

    func remove(_ id: String) async {
        guard !stuckIds.contains(id) else { return }
        ids.removeAll { $0 == id }
    }

    func holdNextAdd() {
        holdsNextAdd = true
    }

    func release() {
        held?.resume()
        held = nil
    }
}

@MainActor
struct StationRegionSyncTests {
    private static func plan(_ name: String, count: Int = StationRegionPlan.maximumRegions) -> [WatchedRegion] {
        (0..<count).map { index in
            WatchedRegion(
                id: "arrival:\(name)\(index)",
                center: Coordinate(48.85 + Double(index) / 1000, 2.35),
                radiusMeters: AutoLiveActivityRules.arrivalRadiusMeters
            )
        }
    }

    private static func ids(of regions: [WatchedRegion]) -> Set<String> {
        Set(regions.map(\.id))
    }

    /// Lets the tasks that wait for the main actor run until they wait for something else.
    private static func letOthersRun() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    @Test func endsWithOnlyTheAreasOfTheLastPlanWhenTwoPlansOverlap() async {
        let monitor = FakeRegionMonitor()
        let sync = StationRegionSync(monitor: monitor)
        let first = Self.plan("a")
        let last = Self.plan("b")

        monitor.holdNextAdd()
        let firstWatch = Task { await sync.watch(first) }
        while !monitor.isHoldingAnAdd {
            await Task.yield()
        }
        let lastWatch = Task { await sync.watch(last) }
        await Self.letOthersRun()
        monitor.release()
        await firstWatch.value
        await lastWatch.value

        #expect(Set(monitor.ids) == Self.ids(of: last))
        #expect(monitor.mostIds <= StationRegionPlan.maximumRegions)
    }

    @Test func neverAsksIOSToWatchMoreThanTheMaximumWhenPlansComeInABurst() async {
        let monitor = FakeRegionMonitor()
        let sync = StationRegionSync(monitor: monitor)
        let plans = ["a", "b", "c", "d"].map { Self.plan($0) }

        monitor.holdNextAdd()
        var watches = [Task { await sync.watch(plans[0]) }]
        while !monitor.isHoldingAnAdd {
            await Task.yield()
        }
        for plan in plans.dropFirst() {
            watches.append(Task { await sync.watch(plan) })
            await Self.letOthersRun()
        }
        monitor.release()
        for watch in watches {
            await watch.value
        }

        #expect(Set(monitor.ids) == Self.ids(of: plans[3]))
        #expect(monitor.mostIds <= StationRegionPlan.maximumRegions)
    }

    @Test func removesAnAreaThatIOSKeptOutOfThePlanAtTheNextPlan() async {
        let monitor = FakeRegionMonitor(ids: ["arrival:old"])
        let sync = StationRegionSync(monitor: monitor)
        let first = Self.plan("a")
        await sync.watch(first)
        await monitor.add(Self.plan("left", count: 1)[0])

        await sync.watch(first)

        #expect(Set(monitor.ids) == Self.ids(of: first))
    }

    @Test func addsAgainAnAreaOfThePlanThatIOSNoLongerKeeps() async {
        let monitor = FakeRegionMonitor()
        let sync = StationRegionSync(monitor: monitor)
        let plan = Self.plan("a")
        await sync.watch(plan)
        await monitor.remove(plan[0].id)

        await sync.watch(plan)

        #expect(Set(monitor.ids) == Self.ids(of: plan))
    }

    @Test func tellsTheWakeLogWhenIOSKeepsAnotherCountThanThePlan() async {
        let storage = InMemoryKeyValueStore()
        let log = WakeLog(storage: storage)
        let monitor = FakeRegionMonitor(ids: ["arrival:stuck"])
        monitor.stuckIds = ["arrival:stuck"]
        let sync = StationRegionSync(monitor: monitor)
        sync.wakeLog = log

        await sync.watch(Self.plan("a"))
        let afterTheLeak = log.entries.map(\.text)
        monitor.stuckIds = []
        await sync.watch(Self.plan("a"))

        #expect(afterTheLeak == ["iOS keeps 21 areas for the app, the plan has 20"])
        #expect(log.entries.count == 1)
    }
}
