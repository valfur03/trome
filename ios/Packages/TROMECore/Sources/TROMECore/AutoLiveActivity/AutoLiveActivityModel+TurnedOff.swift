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
        log(decision.ending)
        state = decision.state
        for action in decision.actions {
            await perform(action)
        }
        await refreshRegions(around: inputs.locationService.position)
    }

    /// The one line of an end that the app did not make: it comes before any next start, as each start first syncs.
    func logEndOutsideTheApp(of shown: AutoLiveActivityState.Shown) {
        log(configuration.rules.endingOutsideTheApp(
            of: shown,
            now: configuration.now(),
            activitiesAreEnabled: liveActivity.areActivitiesEnabled,
            iOSState: services.liveActivityChanges.endState
        ))
    }

    func forgetShownLiveActivity() {
        state = configuration.rules.liveActivityIsGone(
            from: state,
            activitiesAreEnabled: liveActivity.areActivitiesEnabled
        )
    }
}
