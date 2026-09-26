#if DEBUG
import Foundation

extension CoreLocationBackgroundLocationKeeper {
    static let keepRunningInBackgroundArgument = "--keep-running-in-background"

    static func begunIfAsked(by arguments: [String]) -> CoreLocationBackgroundLocationKeeper? {
        guard arguments.contains(keepRunningInBackgroundArgument) else { return nil }
        let keeper = CoreLocationBackgroundLocationKeeper()
        keeper.begin()
        return keeper
    }
}
#endif
