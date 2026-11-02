import Foundation

extension AutoLiveActivityRules {
    func liveActivityIsGone(from state: AutoLiveActivityState, activitiesAreEnabled: Bool) -> AutoLiveActivityState {
        var state = state
        let gone = state.shown
        state.shown = nil
        if !activitiesAreEnabled, let gone, gone.stationId == state.arrivalStationId {
            state.openArrivalStationId = gone.stationId
        }
        return state
    }

    /// Who ended a Live Activity that the app found gone with no end of its own. iOS says it only by the end
    /// state of the Live Activity: `dismissed` when it left the screen (the rider's swipe), `ended` when iOS ended it.
    func endingOutsideTheApp(
        of shown: AutoLiveActivityState.Shown,
        now: Date,
        activitiesAreEnabled: Bool,
        iOSState: LiveActivityEndState?
    ) -> LiveActivityEnding {
        let end: LiveActivityEnding.OutsideEnd
        if !activitiesAreEnabled {
            end = .liveActivitiesTurnedOff
        } else if now.timeIntervalSince(shown.startedAt) >= Self.systemMaximumDuration {
            end = .systemLimit
        } else {
            switch iOSState {
            case .dismissed: end = .swipedAway
            case .ended: end = .endedByIOS
            case nil: end = .noReason
            }
        }
        return .outsideTheApp(end, iOSState: iOSState)
    }

    func automaticModeTurnedOff(state: AutoLiveActivityState) -> Decision {
        guard state.shown != nil else { return Decision(state: state, actions: []) }
        var state = state
        state.shown = nil
        return Decision(state: state, actions: [.end], ending: .automaticStartTurnedOff)
    }
}
