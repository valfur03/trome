import Foundation

extension AutoLiveActivityModel {
    public var exampleStation: Station? {
        catalog.station(withId: ExampleTimetable.stationId)
    }

    public var showsExample: Bool {
        state.exampleStartedAt != nil
    }

    public func exampleTapped() async {
        syncWithSystem()
        await apply(configuration.rules.tapOnTheExample(state: state, now: configuration.now()))
    }

    public func snoozeTappedOnTheLockScreen(for duration: SnoozeDuration) async {
        syncWithSystem()
        switch configuration.rules.answerLockScreenSnooze(state: state) {
        case .endTheExample:
            state.exampleStartedAt = nil
            await endExample()
        case .snooze:
            await snooze(for: duration)
        }
    }

    func restartTheExampleAtTheFront() async {
        guard showsExample else { return }
        await apply(configuration.rules.appComesToTheFront(
            state: state,
            isShowing: liveActivity.isShowing,
            now: configuration.now()
        ))
    }

    func forgetTheExampleIfRemoved() {
        guard state.exampleStartedAt != nil, !liveActivity.isShowing else { return }
        state.exampleStartedAt = nil
    }

    func keepShowingTheExample() async {
        while !Task.isCancelled {
            syncWithSystem()
            let now = configuration.now()
            await apply(configuration.rules.checkTheExample(state: state, isShowing: liveActivity.isShowing, now: now))
            guard let startedAt = state.exampleStartedAt, let station = exampleStation else { return }
            await liveActivity.update(station: station, trains: exampleTrains(startedAt: startedAt, at: station))
            let end = startedAt.addingTimeInterval(configuration.rules.exampleDuration)
            let refresh = now.addingTimeInterval(TimeInterval(NextTrainsModel.refreshInterval.components.seconds))
            let wake = [end, refresh, liveActivity.nextRedrawDate(after: now)].compactMap(\.self).min() ?? end
            do {
                try await configuration.sleep(.seconds(max(1, wake.timeIntervalSince(now).rounded(.up))))
            } catch {
                return
            }
        }
    }

    private func apply(_ decision: AutoLiveActivityRules.ExampleDecision) async {
        state = decision.state
        for action in decision.actions {
            switch action {
            case .show:
                await showExample()
            case .end:
                await endExample()
            }
        }
    }

    private func showExample() async {
        guard let startedAt = state.exampleStartedAt, let station = exampleStation else { return }
        await liveActivity.start(station: station, trains: exampleTrains(startedAt: startedAt, at: station))
        guard liveActivity.isShowing else {
            state.exampleStartedAt = nil
            return
        }
        removedOutsideTheApp = nil
        restartFeed(fetchNow: false)
    }

    private func endExample() async {
        await liveActivity.stop()
        restartFeed(fetchNow: false)
    }

    private func exampleTrains(startedAt: Date, at station: Station) -> NextTrainsState {
        ExampleTimetable(start: startedAt).trains(at: catalog.hubStations(of: station), now: configuration.now())
    }
}
