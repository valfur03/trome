import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityRulesTests {
    func arrivedInTheBackground(at station: Station) -> AutoLiveActivityState {
        var state = AutoLiveActivityState(arrivalStationId: station.id)
        state.openArrivalStationId = station.id
        return state
    }

    @Test func startsAnArrivalInTheBackgroundWhenTheAppIsActiveAtItsStation() {
        let decision = decide(
            arrivedInTheBackground(at: Places.stationA), at: Places.fiftyMetersFromA, appPhase: .active
        )

        #expect(decision.actions == [.start(Places.stationA)])
        #expect(decision.state == showing(Places.stationA))
        #expect(decision.state.openArrivalStationId == nil)
    }

    @Test(arguments: [AppPhase.inactive, .background])
    func keepsAnArrivalInTheBackgroundOpenWhileTheAppIsNotActive(appPhase: AppPhase) {
        let decision = decide(
            arrivedInTheBackground(at: Places.stationA), at: Places.fiftyMetersFromA, appPhase: appPhase
        )

        #expect(decision.actions.isEmpty)
        #expect(decision.state == arrivedInTheBackground(at: Places.stationA))
    }

    @Test func doesNotStartAnArrivalInTheBackgroundWhileSnoozedOrOff() {
        let decision = decide(
            arrivedInTheBackground(at: Places.stationA), at: Places.fiftyMetersFromA, appPhase: .active,
            allowsAutomaticStart: false
        )

        #expect(decision.actions.isEmpty)
    }

    @Test func doesNotStartAnArrivalInTheBackgroundWhileItsStationIsPaused() {
        var state = arrivedInTheBackground(at: Places.stationA)
        state.pause = StationPause(stationId: "a", end: now.addingTimeInterval(60))

        #expect(decide(state, at: Places.fiftyMetersFromA, appPhase: .active).actions.isEmpty)
        #expect(rules.waitsForAResume(state: state, now: now, onArrival: .start) == false)
    }

    @Test func doesNotStartAnArrivalInTheBackgroundBetweenTheArrivalAndStopRadius() {
        let decision = decide(
            arrivedInTheBackground(at: Places.stationA), at: Places.twoHundredMetersFromA, appPhase: .active
        )

        #expect(decision.actions.isEmpty)
        #expect(decision.state == arrivedInTheBackground(at: Places.stationA))
    }

    @Test func closesAnArrivalInTheBackgroundWhenThePhoneLeavesTheStation() {
        let left = decide(arrivedInTheBackground(at: Places.stationA), at: Places.fourHundredMetersFromA)
        let back = decide(left.state, at: Places.fourHundredMetersFromA, appPhase: .active)

        #expect(left.actions.isEmpty)
        #expect(left.state == AutoLiveActivityState())
        #expect(back.actions.isEmpty)
    }

    @Test func aNewArrivalReplacesTheOneInTheBackground() {
        let arrivedAtB = decide(arrivedInTheBackground(at: Places.stationA), at: Places.atB)
        let snoozedAtB = decide(
            arrivedInTheBackground(at: Places.stationA), at: Places.atB, allowsAutomaticStart: false
        )

        #expect(arrivedAtB.actions == [.startInTheBackground(Places.stationB)])
        #expect(arrivedAtB.state == arrivedInTheBackground(at: Places.stationB))
        #expect(snoozedAtB.state.openArrivalStationId == nil)
    }

    @Test func aShownLiveActivityClosesTheArrivalInTheBackground() {
        var state = arrivedInTheBackground(at: Places.stationA)
        state.shown = .init(stationId: "b", startedAt: now, hasBeenNear: false)
        state.shown = nil

        #expect(state.openArrivalStationId == nil)
        #expect(rules.waitsForAResume(state: state, now: now, onArrival: .start) == false)
    }

    @Test func savesTheArrivalInTheBackground() throws {
        let state = arrivedInTheBackground(at: Places.stationA)

        let saved = try JSONDecoder().decode(AutoLiveActivityState.self, from: JSONEncoder().encode(state))

        #expect(saved == state)
    }
}
