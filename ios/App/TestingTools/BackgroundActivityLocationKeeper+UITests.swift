#if DEBUG
import Foundation

extension BackgroundActivityLocationKeeper {
    static let keepRunningInBackgroundArgument = "--keep-running-in-background"

    static func begunIfAsked(by arguments: [String]) -> BackgroundActivityLocationKeeper? {
        guard arguments.contains(keepRunningInBackgroundArgument) else { return nil }
        let keeper = BackgroundActivityLocationKeeper()
        keeper.begin()
        return keeper
    }
}
#endif
