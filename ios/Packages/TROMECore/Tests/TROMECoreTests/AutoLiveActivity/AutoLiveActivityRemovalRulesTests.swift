import Foundation
import Testing
@testable import TROMECore

struct AutoLiveActivityRemovalRulesTests {
    private typealias Places = AutoTestPlaces
    private let rules = AutoLiveActivityRules()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func shown(startedSecondsAgo seconds: TimeInterval = 600) -> AutoLiveActivityState.Shown {
        .init(stationId: "a", startedAt: now.addingTimeInterval(-seconds), hasBeenNear: true)
    }

    private func removal(endedByTheApp: Bool = false, activitiesAreEnabled: Bool = true) -> LiveActivityRemoval {
        LiveActivityRemoval(endedByTheApp: endedByTheApp, activitiesAreEnabled: activitiesAreEnabled)
    }

    @Test func aRemovalByTheRiderPausesItsStationForOneHour() {
        let outcome = rules.outcome(of: removal(), shown: shown(), now: now)

        #expect(outcome == .pause(StationPause(stationId: "a", end: now.addingTimeInterval(3_600))))
    }

    @Test func theAppsOwnEndIsNoSwipe() {
        #expect(rules.outcome(of: removal(endedByTheApp: true), shown: shown(), now: now) == .endedByTheApp)
    }

    @Test func aRemovalWhenTheAppHadNoShownLiveActivityIsNoSwipe() {
        #expect(rules.outcome(of: removal(), shown: nil, now: now) == .noShownLiveActivity)
    }

    @Test func liveActivitiesTurnedOffInSettingsIsNoSwipe() {
        let outcome = rules.outcome(of: removal(activitiesAreEnabled: false), shown: shown(), now: now)

        #expect(outcome == .liveActivitiesTurnedOff)
    }

    @Test(arguments: [8 * 3_600.0, 9 * 3_600.0])
    func theEndOfIOSAfterEightHoursIsNoSwipe(age: TimeInterval) {
        let outcome = rules.outcome(of: removal(), shown: shown(startedSecondsAgo: age), now: now)

        #expect(outcome == .olderThanTheSystemLimit)
    }

    @Test func aLiveActivityJustUnderEightHoursOldStillPauses() {
        let outcome = rules.outcome(of: removal(), shown: shown(startedSecondsAgo: 8 * 3_600 - 1), now: now)

        #expect(outcome == .pause(StationPause(stationId: "a", end: now.addingTimeInterval(3_600))))
    }

    @Test(arguments: [AppPhase.active, .inactive, .background])
    func neitherNotifiesNorStartsAtThePausedStationButRemembersTheArrival(appPhase: AppPhase) {
        let pause = StationPause(stationId: "a", end: now.addingTimeInterval(60))
        let decision = rules.decide(
            state: AutoLiveActivityState(pause: pause),
            position: Places.fiftyMetersFromA,
            now: now,
            onArrival: .init(appPhase: appPhase, allowsAutomaticStart: true),
            catalog: Places.catalog
        )

        #expect(decision.actions.isEmpty)
        #expect(decision.state == AutoLiveActivityState(arrivalStationId: "a", pause: pause))
    }

    @Test func aPauseThatIsOverNoLongerStopsTheArrival() {
        let pause = StationPause(stationId: "a", end: now)
        let decision = rules.decide(
            state: AutoLiveActivityState(pause: pause),
            position: Places.fiftyMetersFromA,
            now: now,
            onArrival: .init(appPhase: .background, allowsAutomaticStart: true),
            catalog: Places.catalog
        )

        #expect(decision.actions == [.notify(Places.stationA)])
    }

    @Test func aPauseAtAnotherStationDoesNotStopTheArrival() {
        let pause = StationPause(stationId: "b", end: now.addingTimeInterval(60))
        let decision = rules.decide(
            state: AutoLiveActivityState(pause: pause),
            position: Places.fiftyMetersFromA,
            now: now,
            onArrival: .init(appPhase: .active, allowsAutomaticStart: true),
            catalog: Places.catalog
        )

        #expect(decision.actions == [.start(Places.stationA)])
    }

    @Test func aStateSavedBeforeThePauseExistedLoadsWithNoPause() throws {
        let storage = InMemoryKeyValueStore()
        storage.set(Data(#"{"arrivalStationId":"a"}"#.utf8), forKey: AutoLiveActivityStore.key)

        #expect(AutoLiveActivityStore(storage: storage).load() == AutoLiveActivityState(arrivalStationId: "a"))
    }

    @Test func savesThePause() {
        let storage = InMemoryKeyValueStore()
        let state = AutoLiveActivityState(
            arrivalStationId: "a",
            pause: StationPause(stationId: "a", end: Date(timeIntervalSince1970: 1_000))
        )

        AutoLiveActivityStore(storage: storage).save(state)

        #expect(AutoLiveActivityStore(storage: storage).load() == state)
    }
}
