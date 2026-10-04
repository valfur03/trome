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

    func automaticModeTurnedOff(state: AutoLiveActivityState) -> Decision {
        guard state.shown != nil else { return Decision(state: state, actions: []) }
        var state = state
        state.shown = nil
        return Decision(state: state, actions: [.end])
    }
}
