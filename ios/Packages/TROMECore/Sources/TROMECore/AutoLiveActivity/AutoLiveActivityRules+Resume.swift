import Foundation

extension AutoLiveActivityRules {
    func takesAResume(state: AutoLiveActivityState, onArrival response: ArrivalResponse) -> Bool {
        response == .start && state.shown == nil
    }

    func resume(
        state: AutoLiveActivityState,
        position: Coordinate?,
        now: Date,
        onArrival response: ArrivalResponse,
        catalog: StationCatalog
    ) -> Decision {
        guard takesAResume(state: state, onArrival: response) else { return Decision(state: state, actions: []) }
        var state = state
        state.arrivalStationId = nil
        return decide(state: state, position: position, now: now, onArrival: response, catalog: catalog)
    }
}
