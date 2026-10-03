import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityRulesTests {
    func resume(
        _ state: AutoLiveActivityState,
        at position: Coordinate?,
        appPhase: AppPhase = .active,
        allowsAutomaticStart: Bool = true
    ) -> AutoLiveActivityRules.Decision {
        rules.resume(
            state: state,
            position: position,
            now: now,
            onArrival: .init(appPhase: appPhase, allowsAutomaticStart: allowsAutomaticStart),
            catalog: Places.catalog
        )
    }

    var arrivedAtA: AutoLiveActivityState {
        AutoLiveActivityState(arrivalStationId: Places.stationA.id)
    }

    @Test func aResumeAtTheStationOfAnArrivalAlreadySeenStartsItsLiveActivityWithNoNotification() {
        let decision = resume(arrivedAtA, at: Places.fiftyMetersFromA)

        #expect(decision.actions == [.start(Places.stationA)])
        #expect(decision.state == showing(Places.stationA))
    }

    @Test func aResumeAtAStationWithNoArrivalSeenStartsItsLiveActivity() {
        let decision = resume(AutoLiveActivityState(), at: Places.atB)

        #expect(decision.actions == [.start(Places.stationB)])
    }

    @Test(arguments: [Places.fourHundredMetersFromA, Places.twoHundredMetersFromA])
    func aResumeAwayFromEveryStationStartsNothingAndSaysNothing(position: Coordinate) {
        let decision = resume(arrivedAtA, at: position)

        #expect(decision.actions.isEmpty)
        #expect(decision.state.shown == nil)
    }

    @Test(arguments: [AppPhase.inactive, .background])
    func aResumeWhileTheAppIsNotActiveChangesNothing(appPhase: AppPhase) {
        let decision = resume(arrivedAtA, at: Places.fiftyMetersFromA, appPhase: appPhase)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == arrivedAtA)
        #expect(rules.takesAResume(state: arrivedAtA, onArrival: .init(appPhase: appPhase, allowsAutomaticStart: true))
            == false)
    }

    @Test func aResumeWhileSnoozedOrOffChangesNothing() {
        let decision = resume(arrivedAtA, at: Places.fiftyMetersFromA, allowsAutomaticStart: false)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == arrivedAtA)
    }

    @Test func aResumeWhileALiveActivityShowsChangesNothing() {
        let shownAtB = showing(Places.stationB)

        let decision = resume(shownAtB, at: Places.fiftyMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == shownAtB)
        #expect(rules.takesAResume(state: shownAtB, onArrival: .start) == false)
    }

    @Test func aResumeAtAPausedStationStartsNothing() {
        var state = arrivedAtA
        state.pause = StationPause(stationId: "a", end: now.addingTimeInterval(60))

        let decision = resume(state, at: Places.fiftyMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.state.shown == nil)
    }

    @Test func aResumeWithNoPositionStartsNothingAndLetsTheNextPositionAtTheStationStartIt() {
        let waiting = resume(arrivedAtA, at: nil)
        let next = decide(waiting.state, at: Places.fiftyMetersFromA, appPhase: .active)

        #expect(waiting.actions.isEmpty)
        #expect(next.actions == [.start(Places.stationA)])
    }
}
