import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityRulesTests {
    func notified(at station: Station) -> AutoLiveActivityState {
        var state = AutoLiveActivityState(arrivalStationId: station.id)
        state.openArrivalStationId = station.id
        return state
    }

    @Test func startsANotifiedArrivalWhenTheAppIsActiveAtItsStationAndWithdrawsItsNotification() {
        let decision = decide(notified(at: Places.stationA), at: Places.fiftyMetersFromA, appPhase: .active)

        #expect(decision.actions == [.start(Places.stationA), .withdrawNotification])
        #expect(decision.state == showing(Places.stationA))
        #expect(decision.state.openArrivalStationId == nil)
    }

    @Test(arguments: [AppPhase.inactive, .background])
    func keepsANotifiedArrivalOpenWhileTheAppIsNotActive(appPhase: AppPhase) {
        let decision = decide(notified(at: Places.stationA), at: Places.fiftyMetersFromA, appPhase: appPhase)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == notified(at: Places.stationA))
    }

    @Test func doesNotStartANotifiedArrivalWhileSnoozedOrOff() {
        let decision = decide(
            notified(at: Places.stationA), at: Places.fiftyMetersFromA, appPhase: .active, allowsAutomaticStart: false
        )

        #expect(decision.actions.isEmpty)
    }

    @Test func doesNotStartANotifiedArrivalWhileItsStationIsPaused() {
        var state = notified(at: Places.stationA)
        state.pause = StationPause(stationId: "a", end: now.addingTimeInterval(60))

        #expect(decide(state, at: Places.fiftyMetersFromA, appPhase: .active).actions.isEmpty)
        #expect(rules.waitsForAResume(state: state, now: now, onArrival: .start) == false)
    }

    @Test func doesNotStartANotifiedArrivalBetweenTheArrivalAndStopRadius() {
        let decision = decide(notified(at: Places.stationA), at: Places.twoHundredMetersFromA, appPhase: .active)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == notified(at: Places.stationA))
    }

    @Test func closesANotifiedArrivalWhenThePhoneLeavesTheStation() {
        let left = decide(notified(at: Places.stationA), at: Places.fourHundredMetersFromA)
        let back = decide(left.state, at: Places.fourHundredMetersFromA, appPhase: .active)

        #expect(left.actions == [.withdrawNotification])
        #expect(left.state == AutoLiveActivityState())
        #expect(back.actions.isEmpty)
    }

    @Test func aNewArrivalReplacesTheNotifiedOne() {
        let notifiedAtB = decide(notified(at: Places.stationA), at: Places.atB)
        let snoozedAtB = decide(notified(at: Places.stationA), at: Places.atB, allowsAutomaticStart: false)

        #expect(notifiedAtB.actions == [.notify(Places.stationB)])
        #expect(notifiedAtB.state == notified(at: Places.stationB))
        #expect(snoozedAtB.state.openArrivalStationId == nil)
    }

    @Test func aShownLiveActivityClosesTheNotifiedArrival() {
        var state = notified(at: Places.stationA)
        state.shown = .init(stationId: "b", startedAt: now, hasBeenNear: false)
        state.shown = nil

        #expect(state.openArrivalStationId == nil)
        #expect(rules.waitsForAResume(state: state, now: now, onArrival: .start) == false)
    }

    @Test func savesTheNotifiedArrival() throws {
        let state = notified(at: Places.stationA)

        let saved = try JSONDecoder().decode(AutoLiveActivityState.self, from: JSONEncoder().encode(state))

        #expect(saved == state)
    }
}
