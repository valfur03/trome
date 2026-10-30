#if DEBUG
import Foundation

extension CoreLocationBackgroundLocationKeeper {
    static let keepRunningInBackgroundArgument = "--keep-running-in-background"
    private static let keepers = NSHashTable<CoreLocationBackgroundLocationKeeper>.weakObjects()
    private(set) static var isEndedForUITests = false

    static func begunIfAsked(by arguments: [String]) -> CoreLocationBackgroundLocationKeeper? {
        guard arguments.contains(keepRunningInBackgroundArgument) else { return nil }
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
