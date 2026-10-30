#if DEBUG
import Foundation

extension CoreLocationBackgroundLocationKeeper {
    static let keepRunningInBackgroundArgument = "--keep-running-in-background"
    // The E2E tests post this Darwin notification before they kill the app. A background session that is still
    // open when the app is killed outlives it, and iOS then starts the app again, at a time that no test controls.
    static let endForUITestsNotification = "TROME.UITests.endBackgroundLocation"
    private static let keepers = NSHashTable<CoreLocationBackgroundLocationKeeper>.weakObjects()
    private static var observesUITests = false
    private(set) static var isEndedForUITests = false

    static func begunIfAsked(by arguments: [String]) -> CoreLocationBackgroundLocationKeeper? {
        guard arguments.contains(keepRunningInBackgroundArgument) else { return nil }
        let keeper = CoreLocationBackgroundLocationKeeper()
        keeper.begin()
        return keeper
    }

    func endWhenUITestsAsk() {
        Self.keepers.add(self)
        guard !Self.observesUITests else { return }
        Self.observesUITests = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in CoreLocationBackgroundLocationKeeper.endAllForUITests() }
            },
            Self.endForUITestsNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static func endAllForUITests() {
        log("end for the UI tests")
        isEndedForUITests = true
        for keeper in keepers.allObjects {
            keeper.end()
        }
    }
}
#endif
