#if DEBUG
import TROMECore

extension AutoLiveActivityModel {
    static let endLiveActivityArgument = "--end-live-activity"

    func endLiveActivityIfAsked(by arguments: [String]) {
        guard arguments.contains(Self.endLiveActivityArgument) else { return }
        Task { await stopByHand() }
    }
}
#endif
