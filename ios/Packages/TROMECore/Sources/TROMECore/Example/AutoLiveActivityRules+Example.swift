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

    func answerLockScreenSnooze(state: AutoLiveActivityState) -> LockScreenSnoozeAnswer {
        state.exampleStartedAt == nil ? .snooze : .endTheExample
    }
}
