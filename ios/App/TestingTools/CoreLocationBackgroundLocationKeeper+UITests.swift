#if DEBUG
import Foundation
import TROMECore

extension CoreLocationBackgroundLocationKeeper {
    static let keepRunningInBackgroundArgument = "--keep-running-in-background"
    private static let keepers = NSHashTable<CoreLocationBackgroundLocationKeeper>.weakObjects()
    private(set) static var isEndedForUITests = false

    /// Stands in for the wake of a station area, which the Simulator cannot watch: the app stays awake in the
    /// background and keeps following the position, so that a moved position reaches the arrival rules.
    static func begunIfAsked(
        by arguments: [String],
        following locationService: LocationService
    ) -> CoreLocationBackgroundLocationKeeper? {
        guard arguments.contains(keepRunningInBackgroundArgument) else { return nil }
        locationService.keepsFollowingOffScreen = true
        let keeper = CoreLocationBackgroundLocationKeeper()
        keeper.begin()
        return keeper
    }

    func letUITestsEndIt() {
        Self.keepers.add(self)
    }

    // After this, no keeper of this process begins again: the E2E test kills the app next.
    static func endAllForUITests() {
        isEndedForUITests = true
        for keeper in keepers.allObjects {
            keeper.end()
        }
    }
}
#endif
