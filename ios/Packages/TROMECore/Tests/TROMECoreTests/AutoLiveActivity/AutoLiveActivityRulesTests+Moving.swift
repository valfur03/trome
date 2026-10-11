import Foundation
import Testing
@testable import TROMECore

/// A rider who moves past stations: while a Live Activity shows, the next station switches it, never notifies.
extension AutoLiveActivityRulesTests {
    @Test(arguments: [AppPhase.active, .inactive, .background], [true, false])
    func switchesAShownLiveActivityToTheNextStationWithNoNotification(appPhase: AppPhase, allowsAutomaticStart: Bool) {
        let decision = decide(
            showing(Places.stationA), at: Places.atB, appPhase: appPhase, allowsAutomaticStart: allowsAutomaticStart
        )

        #expect(decision.actions == [.switchTo(Places.stationB)])
        #expect(decision.arrival == .switched(Places.stationB))
    }

    @Test func saysHowFarTheRiderWasWhenTheLiveActivityEnded() throws {
        let decision = decide(showing(Places.stationA), at: Places.fourHundredMetersFromA)

        #expect(decision.actions == [.withdrawNotification, .end])
        let ending = try #require(decision.ending)
        #expect(ending.summary == "Live Activity ended: 400 m from Station A")
    }

    @Test func notifiesTheNextStationWhenTheLiveActivityEndedOnTheWay() {
        let onTheWay = decide(showing(Places.stationA), at: Places.fourHundredMetersFromA)
        let atB = decide(onTheWay.state, at: Places.atB)

        #expect(atB.actions == [.notify(Places.stationB)])
        #expect(atB.ending == nil)
    }

    @Test func saysTheTimeLimitWhenTheLiveActivityEndsAfterIt() {
        let decision = decide(showing(Places.stationA), at: Places.fiftyMetersFromA, after: 45 * 60)

        #expect(decision.actions == [.end])
        #expect(decision.ending?.summary == "Live Activity ended: 45 min after it started")
    }

    @Test func saysTheSecondsOfAShortenedTimeLimit() {
        #expect(LiveActivityEnding.maximumDuration(30).summary == "Live Activity ended: 30 s after it started")
    }
}
