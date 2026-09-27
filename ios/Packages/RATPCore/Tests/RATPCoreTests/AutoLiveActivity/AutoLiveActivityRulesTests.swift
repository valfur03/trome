import Foundation
import Testing
@testable import RATPCore

enum AutoTestPlaces {
    static let stationA = Station(id: "a", name: "Station A", coordinate: Coordinate(48.8500, 2.3500), lines: [])
    static let stationB = Station(id: "b", name: "Station B", coordinate: Coordinate(48.8500, 2.3540), lines: [])
    static let catalog = StationCatalog(stations: [stationA, stationB])
    static let fiftyMetersFromA = Coordinate(48.85045, 2.3500)
    static let twoHundredMetersFromA = Coordinate(48.8518, 2.3500)
    static let fourHundredMetersFromA = Coordinate(48.8536, 2.3500)
    static let atB = stationB.coordinate
}

struct AutoLiveActivityRulesTests {
    private typealias Places = AutoTestPlaces
    private let rules = AutoLiveActivityRules()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func decide(
        _ state: AutoLiveActivityState = AutoLiveActivityState(),
        at position: Coordinate?,
        appIsActive: Bool = false,
        allowsAutomaticStart: Bool = true,
        after seconds: TimeInterval = 0
    ) -> AutoLiveActivityRules.Decision {
        rules.decide(
            state: state,
            position: position,
            now: now.addingTimeInterval(seconds),
            onArrival: .init(appIsActive: appIsActive, allowsAutomaticStart: allowsAutomaticStart),
            catalog: Places.catalog
        )
    }

    private func showing(_ station: Station, hasBeenNear: Bool = true) -> AutoLiveActivityState {
        AutoLiveActivityState(
            arrivalStationId: hasBeenNear ? station.id : nil,
            shown: .init(stationId: station.id, startedAt: now, hasBeenNear: hasBeenNear)
        )
    }

    @Test func notifiesWhenThePhoneEntersAStationAreaWhileTheAppIsClosed() {
        let decision = decide(at: Places.fiftyMetersFromA)

        #expect(decision.actions == [.notify(Places.stationA)])
        #expect(decision.state == AutoLiveActivityState(arrivalStationId: "a"))
    }

    @Test func startsAtOnceWhenTheAppIsOnScreen() {
        let decision = decide(at: Places.fiftyMetersFromA, appIsActive: true)

        #expect(decision.actions == [.start(Places.stationA)])
        #expect(decision.state == showing(Places.stationA))
    }

    @Test(arguments: [true, false])
    func neitherNotifiesNorStartsWhileSnoozedOrOffButRemembersTheArrival(appIsActive: Bool) {
        let decision = decide(at: Places.fiftyMetersFromA, appIsActive: appIsActive, allowsAutomaticStart: false)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == AutoLiveActivityState(arrivalStationId: "a"))
    }

    @Test func doesNotNotifyAfterTheSnoozeForTheStationOfAnArrivalDuringTheSnooze() {
        let duringSnooze = decide(at: Places.fiftyMetersFromA, allowsAutomaticStart: false)
        let afterSnooze = decide(duringSnooze.state, at: Places.fiftyMetersFromA)

        #expect(afterSnooze.actions.isEmpty)
    }

    @Test func switchesALiveActivityStartedByHandWhileSnoozedOrOff() {
        let decision = decide(showing(Places.stationA), at: Places.atB, allowsAutomaticStart: false)

        #expect(decision.actions == [.switchTo(Places.stationB)])
    }

    @Test func respondsToAnArrivalByStartingOnlyWhenTheAppIsOnScreenAndTheAutomaticModeAllowsIt() {
        typealias Response = AutoLiveActivityRules.ArrivalResponse

        #expect(Response(appIsActive: true, allowsAutomaticStart: true) == .start)
        #expect(Response(appIsActive: false, allowsAutomaticStart: true) == .notify)
        #expect(Response(appIsActive: true, allowsAutomaticStart: false) == .none)
        #expect(Response(appIsActive: false, allowsAutomaticStart: false) == .none)
    }

    @Test func doesNothingOutsideTheArrivalRadius() {
        let decision = decide(at: Places.twoHundredMetersFromA, appIsActive: true)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == AutoLiveActivityState())
    }

    @Test func doesNotNotifyTwiceForTheSameArrival() {
        let first = decide(at: Places.fiftyMetersFromA)
        let movedOut = decide(first.state, at: Places.twoHundredMetersFromA)
        let back = decide(movedOut.state, at: Places.fiftyMetersFromA)

        #expect(movedOut.actions.isEmpty)
        #expect(back.actions.isEmpty)
    }

    @Test func notifiesAgainAfterThePhoneLeftTheStationArea() {
        let first = decide(at: Places.fiftyMetersFromA)
        let left = decide(first.state, at: Places.fourHundredMetersFromA)
        let back = decide(left.state, at: Places.fiftyMetersFromA)

        #expect(left.actions == [.withdrawNotification])
        #expect(left.state.arrivalStationId == nil)
        #expect(back.actions == [.notify(Places.stationA)])
    }

    @Test func doesNotStartAgainAfterAStopByHandInTheSameArea() {
        let state = AutoLiveActivityState(arrivalStationId: "a")

        #expect(decide(state, at: Places.fiftyMetersFromA, appIsActive: true).actions.isEmpty)
    }

    @Test func switchesToANearerStationInsteadOfNotifying() {
        let decision = decide(showing(Places.stationA), at: Places.atB)

        #expect(decision.actions == [.switchTo(Places.stationB)])
        #expect(decision.state.shown == .init(stationId: "b", startedAt: now, hasBeenNear: true))
        #expect(decision.state.arrivalStationId == "b")
    }

    @Test func switchesAManualLiveActivityWhenThePhoneEntersAnotherStationArea() {
        let decision = decide(showing(Places.stationB, hasBeenNear: false), at: Places.fiftyMetersFromA)

        #expect(decision.actions == [.switchTo(Places.stationA)])
    }

    @Test func keepsTheLiveActivityBetweenTheArrivalAndStopRadius() {
        let decision = decide(showing(Places.stationA), at: Places.twoHundredMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == showing(Places.stationA))
    }

    @Test func endsTheLiveActivityWhenThePhoneMovesAwayFromTheStation() {
        let decision = decide(showing(Places.stationA), at: Places.fourHundredMetersFromA)

        #expect(decision.actions == [.withdrawNotification, .end])
        #expect(decision.state == AutoLiveActivityState())
    }

    @Test func keepsALiveActivityStartedByHandFarFromItsStation() {
        let decision = decide(showing(Places.stationA, hasBeenNear: false), at: Places.fourHundredMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.state == showing(Places.stationA, hasBeenNear: false))
    }

    @Test func endsALiveActivityStartedByHandOnceThePhoneWasNearAndMovesAway() {
        let near = decide(showing(Places.stationA, hasBeenNear: false), at: Places.twoHundredMetersFromA)
        let away = decide(near.state, at: Places.fourHundredMetersFromA)

        #expect(near.state.shown?.hasBeenNear == true)
        #expect(away.actions == [.end])
    }

    @Test func endsTheLiveActivityAfterTheMaximumDuration() {
        let decision = decide(showing(Places.stationA), at: nil, after: 45 * 60)

        #expect(decision.actions == [.end])
        #expect(decision.state == AutoLiveActivityState(arrivalStationId: "a"))
    }

    @Test func keepsTheLiveActivityJustBeforeTheMaximumDuration() {
        #expect(decide(showing(Places.stationA), at: nil, after: 45 * 60 - 1).actions.isEmpty)
    }

    @Test func doesNotStartAgainAfterTheMaximumDurationInTheSameArea() {
        let decision = decide(showing(Places.stationA), at: Places.fiftyMetersFromA, appIsActive: true, after: 45 * 60)

        #expect(decision.actions == [.end])
    }

    @Test func usesTheConfiguredMaximumDuration() {
        let shortRules = AutoLiveActivityRules(maximumDuration: 60)

        let decision = shortRules.decide(
            state: showing(Places.stationA),
            position: nil,
            now: now.addingTimeInterval(60),
            onArrival: .start,
            catalog: Places.catalog
        )

        #expect(decision.actions == [.end])
    }

    private func fix(accuracy: Double, secondsAgo: TimeInterval = 0) -> PositionFix {
        PositionFix(
            coordinate: Places.fiftyMetersFromA,
            accuracyMeters: accuracy,
            timestamp: now.addingTimeInterval(-secondsAgo)
        )
    }

    @Test func trustsAPreciseAndRecentPosition() {
        #expect(AutoLiveActivityRules.trusts(fix(accuracy: 100, secondsAgo: 15), now: now))
    }

    @Test(arguments: [100.1, 800, -1])
    func doesNotTrustARoughOrInvalidPosition(accuracy: Double) {
        #expect(AutoLiveActivityRules.trusts(fix(accuracy: accuracy), now: now) == false)
    }

    @Test func doesNotTrustAnOldPosition() {
        #expect(AutoLiveActivityRules.trusts(fix(accuracy: 10, secondsAgo: 16), now: now) == false)
    }

    @Test func trustsAPositionFromAFewSecondsAhead() {
        #expect(AutoLiveActivityRules.trusts(fix(accuracy: 10, secondsAgo: -15), now: now))
    }

    @Test func doesNotTrustAPositionFromFarAhead() {
        #expect(AutoLiveActivityRules.trusts(fix(accuracy: 10, secondsAgo: -16), now: now) == false)
    }

    @Test func usesTheGivenMaximumAge() {
        let oldFix = fix(accuracy: 10, secondsAgo: 120)

        #expect(AutoLiveActivityRules.trusts(oldFix, now: now, maximumAge: 120))
        #expect(AutoLiveActivityRules.trusts(oldFix, now: now, maximumAge: 119) == false)
    }
}
