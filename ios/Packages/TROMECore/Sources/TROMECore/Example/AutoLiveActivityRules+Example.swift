import Foundation

extension AutoLiveActivityRules {
    public static let defaultExampleDuration: TimeInterval = 10 * 60

    enum ExampleAction: Equatable, Sendable {
        case show
        case end
    }

    struct ExampleDecision: Equatable, Sendable {
        var state: AutoLiveActivityState
        var actions: [ExampleAction] = []
    }

    enum LockScreenSnoozeAnswer: Equatable, Sendable {
        case endTheExample
        case snooze
    }

    func tapOnTheExample(state: AutoLiveActivityState, now: Date) -> ExampleDecision {
        guard state.shown == nil else { return ExampleDecision(state: state) }
        var state = state
        state.exampleStartedAt = now
        return ExampleDecision(state: state, actions: [.show])
    }

    func checkTheExample(state: AutoLiveActivityState, isShowing: Bool, now: Date) -> ExampleDecision {
        guard let startedAt = state.exampleStartedAt else { return ExampleDecision(state: state) }
        var state = state
        guard isShowing else {
            state.exampleStartedAt = nil
            return ExampleDecision(state: state)
        }
        guard now.timeIntervalSince(startedAt) >= exampleDuration else { return ExampleDecision(state: state) }
        state.exampleStartedAt = nil
        return ExampleDecision(state: state, actions: [.end])
    }

    /// The app at the front restarts the example that still shows, as a tap on the row does,
    /// so that the lock screen counts down for its full first minutes again once the phone locks.
    /// An example past its duration ends instead, and an ended one stays ended.
    func appComesToTheFront(state: AutoLiveActivityState, isShowing: Bool, now: Date) -> ExampleDecision {
        let checked = checkTheExample(state: state, isShowing: isShowing, now: now)
        guard checked.actions.isEmpty, checked.state.exampleStartedAt != nil else { return checked }
        return tapOnTheExample(state: checked.state, now: now)
    }

    func answerLockScreenSnooze(state: AutoLiveActivityState) -> LockScreenSnoozeAnswer {
        state.exampleStartedAt == nil ? .snooze : .endTheExample
    }
}
