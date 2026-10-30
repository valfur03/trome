import Foundation

extension AutoLiveActivityRules {
    /// A Live Activity shows that the app did not start: with a start that the server took, it is the one that the
    /// push brought. It is followed from the server's answer, so that the 45 minutes count from the start, also
    /// when the app sees it later; the rider was within 150 meters of the station at the ask.
    func adoptThePushedLiveActivity(state: AutoLiveActivityState) -> AutoLiveActivityState? {
        guard state.shown == nil, state.exampleStartedAt == nil, let pushed = state.pushedStart else { return nil }
        var adopted = state
        adopted.shown = .init(
            stationId: pushed.stationId, startedAt: pushed.answeredAt, hasBeenNear: true, isStartedByThePush: true
        )
        return adopted
    }
}
