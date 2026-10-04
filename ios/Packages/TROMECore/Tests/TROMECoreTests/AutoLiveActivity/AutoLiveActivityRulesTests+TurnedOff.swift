import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityRulesTests {
    func decideWithLiveActivitiesOff(
        _ state: AutoLiveActivityState = AutoLiveActivityState(),
        at position: Coordinate?,
        appPhase: AppPhase = .active
    ) -> AutoLiveActivityRules.Decision {
        rules.decide(
            state: state,
            position: position,
            now: now,
            onArrival: .init(appPhase: appPhase, allowsAutomaticStart: true, activitiesAreEnabled: false),
            catalog: Places.catalog
        )
    }

    @Test func anArrivalWithTheAppOpenAndLiveActivitiesOffStartsNothingNotifiesNothingAndStaysOpen() {
        let decision = decideWithLiveActivitiesOff(at: Places.fiftyMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == notified(at: Places.stationA))
    }

    @Test func anArrivalWithTheAppClosedAndLiveActivitiesOffStillNotifies() {
        let decision = decideWithLiveActivitiesOff(at: Places.fiftyMetersFromA, appPhase: .background)

        #expect(decision.actions == [.notify(Places.stationA)])
    }

    @Test func anArrivalKeptOpenWhileLiveActivitiesWereOffStartsOnceTheyAreOnWithTheAppOpen() {
        let off = decideWithLiveActivitiesOff(at: Places.fiftyMetersFromA)

        let turnedOn = decide(off.state, at: Places.fiftyMetersFromA, appPhase: .active)

        #expect(turnedOn.actions == [.start(Places.stationA), .withdrawNotification])
        #expect(turnedOn.state == showing(Places.stationA))
        #expect(rules.waitsForAResume(state: off.state, now: now, onArrival: .start))
        #expect(rules.waitsForAResume(state: off.state, now: now, onArrival: .keepOpen) == false)
    }

    @Test func aLiveActivityGoneBecauseLiveActivitiesAreOffKeepsItsArrivalOpen() {
        let state = rules.liveActivityIsGone(from: showing(Places.stationA), activitiesAreEnabled: false)

        #expect(state == notified(at: Places.stationA))
        #expect(rules.waitsForAResume(state: state, now: now, onArrival: .start))
    }

    @Test func aLiveActivityGoneWithLiveActivitiesOnUsesUpItsArrival() {
        let state = rules.liveActivityIsGone(from: showing(Places.stationA), activitiesAreEnabled: true)

        #expect(state == AutoLiveActivityState(arrivalStationId: Places.stationA.id))
        #expect(rules.waitsForAResume(state: state, now: now, onArrival: .start) == false)
    }

    @Test func aLiveActivityGoneAwayFromItsArrivalKeepsNothingOpen() {
        let shownAwayFromItsStation = showing(Places.stationA, hasBeenNear: false)

        let state = rules.liveActivityIsGone(from: shownAwayFromItsStation, activitiesAreEnabled: false)

        #expect(state == AutoLiveActivityState())
    }

    @Test func aResumeWithLiveActivitiesOffKeepsTheArrivalAtTheStationOpen() {
        #expect(rules.takesAResume(state: arrivedAtA, onArrival: .keepOpen))

        let decision = rules.resume(
            state: arrivedAtA,
            position: Places.fiftyMetersFromA,
            now: now,
            onArrival: .keepOpen,
            catalog: Places.catalog
        )

        #expect(decision.actions.isEmpty)
        #expect(decision.state == notified(at: Places.stationA))
    }

    @Test func turningTheAutomaticModeOffEndsTheShownLiveActivity() {
        let decision = rules.automaticModeTurnedOff(state: showing(Places.stationA))

        #expect(decision.actions == [.end])
        #expect(decision.state == AutoLiveActivityState(arrivalStationId: Places.stationA.id))
    }

    @Test func turningTheAutomaticModeOffWithNoLiveActivityDoesNothing() {
        let decision = rules.automaticModeTurnedOff(state: arrivedAtA)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == arrivedAtA)
    }
}
