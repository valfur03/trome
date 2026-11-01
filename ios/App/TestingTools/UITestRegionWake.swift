#if DEBUG
import Foundation
import TROMECore

// The Simulator cannot watch regions (in the iOS 27 Simulator, `isMonitoringAvailable` is false), so it never wakes
// the app at a station. An E2E test posts `entered` with the id of an arrival area (a Darwin notification) in place
// of the event of iOS: the app runs the handler of a real event, in the background, from the last position of iOS.
// A Darwin notification has no content, so the app listens to one name for each arrival area of its plan. It posts
// `handled` when its handler returns, so that the test looks for a notification only after the decision.
@MainActor
enum UITestRegionWake {
    nonisolated static let enteredSignalPrefix = "TROME.UITests.region.entered."
    static let handledSignal = "TROME.UITests.region.handled"
    private static weak var watcher: CoreLocationStationRegionWatcher?
    private static var listenedRegionIds: Set<String> = []

    static func listen(forRegions regionIds: [String], of watcher: CoreLocationStationRegionWatcher) {
        self.watcher = watcher
        let arrivalIds = regionIds.filter { WatchedRegion.arrivalStationId(inRegionId: $0) != nil }
        for regionId in arrivalIds where listenedRegionIds.insert(regionId).inserted {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                { _, _, name, _, _ in
                    guard let signal = name?.rawValue as String? else { return }
                    let regionId = String(signal.dropFirst(UITestRegionWake.enteredSignalPrefix.count))
                    Task { @MainActor in await UITestRegionWake.enter(regionId) }
                },
                (enteredSignalPrefix + regionId) as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    private static func enter(_ regionId: String) async {
        guard let watcher, await watcher.enterForUITests(regionId) else { return }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(handledSignal as CFString),
            nil,
            nil,
            true
        )
    }
}
#endif
