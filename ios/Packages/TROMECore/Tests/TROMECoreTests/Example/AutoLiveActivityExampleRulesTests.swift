import Foundation
import Testing
@testable import TROMECore

struct AutoLiveActivityExampleRulesTests {
    private typealias Places = AutoTestPlaces
    private let rules = AutoLiveActivityRules()
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let pause = StationPause(stationId: "b", end: Date(timeIntervalSince1970: 1_003_600))

    private func showingTheExample(startedSecondsAgo seconds: TimeInterval = 60) -> AutoLiveActivityState {
        var state = AutoLiveActivityState(pause: pause)
        state.exampleStartedAt = now.addingTimeInterval(-seconds)
        return state
    }

    @Test func aTapShowsTheExampleFromNow() {
        let decision = rules.tapOnTheExample(state: AutoLiveActivityState(pause: pause), now: now)

        #expect(decision.actions == [.show])
        #expect(decision.state.exampleStartedAt == now)
        #expect(decision.state.pause == pause)
    }

    @Test func aSecondTapRestartsTheExampleWithFreshTimes() {
        let decision = rules.tapOnTheExample(state: showingTheExample(startedSecondsAgo: 300), now: now)

        #expect(decision.actions == [.show])
        #expect(decision.state.exampleStartedAt == now)
    }

    @Test func aTapWhileRealTrainsShowStartsNothing() {
        let state = AutoLiveActivityState(shown: .init(stationId: "a", startedAt: now, hasBeenNear: true))

        let decision = rules.tapOnTheExample(state: state, now: now)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == state)
    }

    @Test func theExampleGoesOnBeforeItsTenMinutes() {
        let state = showingTheExample(startedSecondsAgo: 599)

        let decision = rules.checkTheExample(state: state, isShowing: true, now: now)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == state)
    }

    @Test(arguments: [600.0, 3_600])
    func theExampleEndsByItselfAfterTenMinutes(startedSecondsAgo seconds: TimeInterval) {
        let decision = rules.checkTheExample(state: showingTheExample(startedSecondsAgo: seconds), isShowing: true, now: now)

        #expect(decision.actions == [.end])
        #expect(decision.state.exampleStartedAt == nil)
        #expect(decision.state.pause == pause)
    }

    @Test func aShorterDurationEndsItSooner() {
        let rules = AutoLiveActivityRules(exampleDuration: 60)

        let decision = rules.checkTheExample(state: showingTheExample(startedSecondsAgo: 60), isShowing: true, now: now)

        #expect(decision.actions == [.end])
    }

    @Test func anExampleThatIOSNoLongerShowsIsForgottenWithNoAction() {
        let decision = rules.checkTheExample(state: showingTheExample(), isShowing: false, now: now)

        #expect(decision.actions.isEmpty)
        #expect(decision.state.exampleStartedAt == nil)
        #expect(decision.state.pause == pause)
    }

    @Test func aSwipeOfTheExampleSetsNoPause() {
        let removal = LiveActivityRemoval(endedByTheApp: false, activitiesAreEnabled: true)

        #expect(rules.outcome(of: removal, shown: showingTheExample().shown, now: now) == .noShownLiveActivity)
    }

    @Test func aSnoozeButtonOfTheExampleEndsItAndSnoozesNothing() {
        #expect(rules.answerLockScreenSnooze(state: showingTheExample()) == .endTheExample)
        #expect(rules.answerLockScreenSnooze(state: AutoLiveActivityState()) == .snooze)
    }

    @Test func aRealArrivalReplacesTheExample() {
        let decision = rules.decide(
            state: showingTheExample(),
            position: Places.fiftyMetersFromA,
            now: now,
            onArrival: .start,
            catalog: Places.catalog
        )

        #expect(decision.actions == [.start(Places.stationA)])
        #expect(decision.state.shown?.stationId == "a")
        #expect(decision.state.exampleStartedAt == nil)
    }

    @Test func anArrivalThatIsOnlyNotifiedKeepsTheExample() {
        let state = showingTheExample()

        let decision = rules.decide(
            state: state,
            position: Places.fiftyMetersFromA,
            now: now,
            onArrival: .notify,
            catalog: Places.catalog
        )

        #expect(decision.actions == [.notify(Places.stationA)])
        #expect(decision.state.exampleStartedAt == state.exampleStartedAt)
    }

    @Test func theExampleIsSavedWithTheState() throws {
        let state = showingTheExample()
        let data = try JSONEncoder().encode(state)

        #expect(try JSONDecoder().decode(AutoLiveActivityState.self, from: data).exampleStartedAt == state.exampleStartedAt)
    }
}
