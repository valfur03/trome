#if DEBUG
import Foundation
import TROMECore

extension CoreLocationBackgroundLocationKeeper {
    private static let keepers = NSHashTable<CoreLocationBackgroundLocationKeeper>.weakObjects()
    private(set) static var isEndedForUITests = false

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
