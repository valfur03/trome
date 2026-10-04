import Foundation

extension AutoLiveActivityModel {
    public var liveActivityProblem: StationLiveActivityError? {
        if let startError = liveActivity.startError {
            return startError
        }
        guard !liveActivity.areActivitiesEnabled, inputs.automaticMode.mode != .turnedOff else { return nil }
        return .turnedOff
    }

    func automaticModeTurnedOff() async {
        syncWithSystem()
        let decision = configuration.rules.automaticModeTurnedOff(state: state)
        guard !decision.actions.isEmpty else { return }
        state = decision.state
        for action in decision.actions {
            await perform(action)
        }
        await refreshRegions(around: inputs.locationService.position)
    }

    func forgetShownLiveActivity() {
        state = configuration.rules.liveActivityIsGone(
            from: state,
            activitiesAreEnabled: liveActivity.areActivitiesEnabled
        )
    }
}
