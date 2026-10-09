import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityRulesTests {
    func leaveStopArea(of station: Station, _ state: AutoLiveActivityState) -> AutoLiveActivityRules.Decision {
        rules.leaveStopArea(of: station.id, state: state, catalog: Places.catalog)
    }

    @Test func forgetsTheArrivalWhenIOSSaysThePhoneLeftTheStopAreaWithNoPosition() {
        let left = leaveStopArea(of: Places.stationA, notified(at: Places.stationA))

        #expect(left.state == AutoLiveActivityState())
        #expect(left.actions == [.withdrawNotification])
        #expect(left.arrival == .left(Places.stationA))
    }

    @Test func notifiesAgainWhenTheRiderComesBackAfterLeavingTheStopArea() {
        let left = leaveStopArea(of: Places.stationA, notified(at: Places.stationA))

        let back = decide(left.state, at: Places.fiftyMetersFromA, after: 24 * 3_600)

        #expect(back.actions == [.notify(Places.stationA)])
    }

    @Test func keepsTheArrivalWhenThePhoneLeavesTheStopAreaOfAnotherStation() {
        let state = notified(at: Places.stationA)

        let left = leaveStopArea(of: Places.stationB, state)

        #expect(left.state == state)
        #expect(left.actions.isEmpty)
        #expect(left.arrival == nil)
    }

    @Test func notifiesOnceWhileTheRiderMovesInsideTheStopArea() {
        let arrived = decide(at: Places.fiftyMetersFromA)
        let moved = decide(arrived.state, at: Places.twoHundredMetersFromA, after: 60)
        let back = decide(moved.state, at: Places.fiftyMetersFromA, after: 120)

        #expect(arrived.actions == [.notify(Places.stationA)])
        #expect(moved.actions.isEmpty)
        #expect(back.actions.isEmpty)
        #expect(back.arrival == .alreadyArrived(Places.stationA))
    }

    @Test func staysQuietAtAPausedStationAfterALeaveAndAReturn() {
        let pause = StationPause(stationId: "a", end: now.addingTimeInterval(StationPause.duration))
        let state = AutoLiveActivityState(arrivalStationId: "a", pause: pause)

        let left = leaveStopArea(of: Places.stationA, state)
        let back = decide(left.state, at: Places.fiftyMetersFromA, after: 60)

        #expect(back.actions.isEmpty)
        #expect(back.arrival == .paused(Places.stationA, until: pause.end))
    }

    @Test func staysQuietWhileSnoozedAfterALeaveAndAReturn() {
        let left = leaveStopArea(of: Places.stationA, AutoLiveActivityState(arrivalStationId: "a"))

        let back = decide(left.state, at: Places.fiftyMetersFromA, allowsAutomaticStart: false, after: 60)

        #expect(back.actions.isEmpty)
        #expect(back.arrival == .automaticStartOff(Places.stationA))
    }

    @Test func notifiesOnceForAWaitingArrivalAfterIOSClosedTheApp() throws {
        let covered = decide(at: Places.fiftyMetersFromA, appPhase: .inactive)
        let relaunched = try JSONDecoder().decode(
            AutoLiveActivityState.self, from: JSONEncoder().encode(covered.state)
        )

        let wake = decide(relaunched, at: Places.fiftyMetersFromA, after: 300)
        let nextWake = decide(wake.state, at: Places.fiftyMetersFromA, after: 400)

        #expect(wake.actions == [.notify(Places.stationA)])
        #expect(nextWake.actions.isEmpty)
    }

    @Test func startsOnceAWaitingArrivalAfterIOSClosedTheAppAndTheRiderOpensIt() throws {
        let covered = decide(at: Places.fiftyMetersFromA, appPhase: .inactive)
        let relaunched = try JSONDecoder().decode(
            AutoLiveActivityState.self, from: JSONEncoder().encode(covered.state)
        )

        let opened = decide(relaunched, at: Places.fiftyMetersFromA, appPhase: .active, after: 300)
        let stillOpen = decide(opened.state, at: nil, appPhase: .active, after: 301)

        #expect(opened.actions == [.start(Places.stationA)])
        #expect(stillOpen.actions.isEmpty)
    }

    @Test func startsOnceAWaitingArrivalAfterNewPositionsBehindThePopup() {
        let covered = decide(at: Places.fiftyMetersFromA, appPhase: .inactive)
        let moved = decide(covered.state, at: Places.fiftyMetersFromA, appPhase: .inactive, after: 10)
        let active = decide(moved.state, at: Places.fiftyMetersFromA, appPhase: .active, after: 20)
        let stillActive = decide(active.state, at: nil, appPhase: .active, after: 21)

        #expect(moved.actions.isEmpty)
        #expect(active.actions == [.start(Places.stationA)])
        #expect(stillActive.actions.isEmpty)
    }

    @Test func forgetsAWaitingArrivalWhenIOSSaysThePhoneLeftTheStopArea() {
        let covered = decide(at: Places.fiftyMetersFromA, appPhase: .inactive)

        let left = leaveStopArea(of: Places.stationA, covered.state)
        let active = decide(left.state, at: nil, appPhase: .active)

        #expect(left.state == AutoLiveActivityState())
        #expect(active.actions.isEmpty)
    }
}
