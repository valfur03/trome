import Foundation

extension AutoLiveActivityRules {
    /// iOS says that the phone left the stop area of a station. It counts as leaving the arrival there,
    /// even when iOS gives no position, or one too old or too rough to trust:
    /// so the next arrival at this station notifies again.
    func leaveStopArea(
        of stationId: String,
        state: AutoLiveActivityState,
        catalog: StationCatalog
    ) -> Decision {
        var decision = Decision(state: state, actions: [])
        guard stationId == state.arrivalStationId ?? state.pendingArrivalStationId else { return decision }
        decision.forgetArrival()
        decision.arrival = catalog.station(withId: stationId).map(ArrivalOutcome.left)
        return decision
    }
}
