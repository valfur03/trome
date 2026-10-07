import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityRulesTests {
    @Test func saysItNotifiedWhenTheClosedAppReachesAStation() {
        let decision = decide(at: Places.fiftyMetersFromA)

        #expect(decision.arrival == .notified(Places.stationA))
    }

    @Test func saysTheSameArrivalStopsASecondNotification() {
        let decision = decide(AutoLiveActivityState(arrivalStationId: "a"), at: Places.fiftyMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.arrival == .alreadyArrived(Places.stationA))
    }

    @Test func namesTheNearestStationWhenNoneIsWithinTheArrivalRadius() {
        let decision = decide(at: Places.twoHundredMetersFromA)

        guard case .noStationNear(let nearest?) = decision.arrival else {
            Issue.record("Expected the nearest station, got \(String(describing: decision.arrival))")
            return
        }
        #expect(nearest.station == Places.stationA)
        #expect((190...210).contains(nearest.distanceMeters))
    }

    @Test func saysASnoozeOrTheOffSwitchStopsTheNotification() {
        let decision = decide(at: Places.fiftyMetersFromA, allowsAutomaticStart: false)

        #expect(decision.arrival == .automaticStartOff(Places.stationA))
    }

    @Test func saysAPauseStopsTheNotificationAndUntilWhen() {
        let end = now.addingTimeInterval(600)
        let paused = AutoLiveActivityState(pause: StationPause(stationId: "a", end: end))

        let decision = decide(paused, at: Places.fiftyMetersFromA)

        #expect(decision.actions.isEmpty)
        #expect(decision.arrival == .paused(Places.stationA, until: end))
    }

    @Test func saysTheLiveActivityAlreadyShowsThisStation() {
        let shown = AutoLiveActivityState(shown: .init(stationId: "a", startedAt: now, hasBeenNear: false))

        let decision = decide(shown, at: Places.fiftyMetersFromA)

        #expect(decision.arrival == .alreadyShown(Places.stationA))
    }

    @Test func saysTheLiveActivitySwitchedOrStarted() {
        #expect(decide(showing(Places.stationA), at: Places.atB).arrival == .switched(Places.stationB))
        #expect(decide(at: Places.fiftyMetersFromA, appPhase: .active).arrival == .started(Places.stationA))
    }

    @Test func saysAPopupMakesTheArrivalWait() {
        let decision = decide(at: Places.fiftyMetersFromA, appPhase: .inactive)

        #expect(decision.arrival == .waitsForTheApp(Places.stationA))
    }

    @Test func saysTheShownStationRatherThanTheSameArrivalWhileItsLiveActivityShows() {
        #expect(decide(showing(Places.stationA), at: Places.fiftyMetersFromA).arrival == .alreadyShown(Places.stationA))
    }

    @Test func logsAWalkAwayFromTheStationsOnlyWhenTheNearestStationChanges() {
        let near = NearbyStation(station: Places.stationA, distanceMeters: 300)
        let nearer = NearbyStation(station: Places.stationA, distanceMeters: 200)
        let other = NearbyStation(station: Places.stationB, distanceMeters: 300)

        #expect(ArrivalOutcome.noStationNear(near).logKey == ArrivalOutcome.noStationNear(nearer).logKey)
        #expect(ArrivalOutcome.noStationNear(near).logKey != ArrivalOutcome.noStationNear(other).logKey)
        let notified = ArrivalOutcome.notified(Places.stationA)
        #expect(notified.logKey != ArrivalOutcome.alreadyArrived(Places.stationA).logKey)
    }
}
