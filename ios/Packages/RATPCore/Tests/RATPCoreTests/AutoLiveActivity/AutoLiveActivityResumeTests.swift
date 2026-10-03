import Foundation
import Testing
@testable import RATPCore

extension AutoLiveActivityModelTests {
    func pausedAtAWithTheAppOpen(_ model: AutoLiveActivityModel, heldPositionAge: TimeInterval) async {
        await pausedAtA(model)
        clock.advance(by: heldPositionAge)
        await activate(model)
    }

    @Test func aResumeWithAHeldFreshPositionStartsWithNoRequest() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 10)

        await model.cancelPause()

        #expect(model.pausedStation == nil)
        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 2)
        #expect(gps.currentFixRequestCount == 0)
        #expect(model.cannotFindPosition == false)
    }

    @Test func aResumeWithAnOldHeldPositionAsksIOSAndStartsOnItsAnswer() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 45)

        await model.cancelPause()

        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 2)
        #expect(gps.currentFixRequestCount == 1)
        #expect(model.cannotFindPosition == false)
    }

    @Test func aResumeWithNoAnswerFromIOSUsesAHeldPositionOfAtMost2Minutes() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 100)
        gps.givesACurrentFix = false

        await model.cancelPause()

        #expect(model.pausedStation == nil)
        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 2)
        #expect(model.cannotFindPosition == false)
    }

    @Test func aResumeWithNoUsablePositionEndsThePauseStartsNothingAndSaysSo() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 121)
        gps.givesACurrentFix = false

        await model.cancelPause()

        #expect(model.pausedStation == nil)
        #expect(model.shownStation == nil)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition)
    }

    @Test func aResumeWithAnImprecisePositionStartsNothingAndSaysSo() async {
        let model = makeModel()
        await pausedAtA(model)
        gps.report(PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 300, timestamp: clock.now))
        await waitUntil { locationService.fix?.accuracyMeters == 300 }
        await activate(model)
        gps.givesACurrentFix = false

        await model.cancelPause()

        #expect(model.pausedStation == nil)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition)
    }

    @Test func aResumeFarFromEveryStationStartsNothingAndSaysNothing() async {
        let model = makeModel()
        await pausedAtA(model)
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { locationService.position == Places.fourHundredMetersFromA }
        clock.advance(by: 45)
        await activate(model)

        await model.cancelPause()

        #expect(gps.currentFixRequestCount == 1)
        #expect(model.pausedStation == nil)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition == false)
    }

    @Test func aResumeWaitsAtMost5SecondsForIOSThenTheLateAnswerStartsTheLiveActivity() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 121)
        gps.holdsTheCurrentFixRequest = true
        clock.letTimersFire(upTo: 5)

        await model.cancelPause()
        #expect(model.pausedStation == nil)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition)

        gps.answerTheHeldRequests()
        await waitUntil { client.started.count == 2 }
        #expect(model.shownStation == Places.stationA)
        #expect(model.cannotFindPosition == false)
    }

    @Test func theNoPositionLineGoesWhenAUsablePositionArrives() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 121)
        gps.givesACurrentFix = false
        await model.cancelPause()

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.started.count == 2 }

        #expect(model.shownStation == Places.stationA)
        #expect(model.cannotFindPosition == false)
    }

    @Test func aLaterResumeOnAHeldPositionRemovesTheNoPositionLine() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 121)
        gps.givesACurrentFix = false
        await model.cancelPause()

        let heldFor100Seconds = PositionFix(
            coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: clock.now - 100
        )
        await model.resume(at: heldFor100Seconds)

        #expect(model.shownStation == Places.stationA)
        #expect(model.cannotFindPosition == false)
    }

    @Test func theNoPositionLineGoesWhenTheAppLeavesTheFront() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 121)
        gps.givesACurrentFix = false
        await model.cancelPause()

        model.setAppPhase(.inactive)

        #expect(model.cannotFindPosition == false)
    }

    @Test func anArrivalByItselfStillNeedsAPositionOfAtMost15Seconds() async {
        let model = makeModel()
        await activate(model)
        let watchedBefore = watcher.watched.count

        gps.report(PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: clock.now - 16))
        await waitUntil { watcher.watched.count > watchedBefore }

        #expect(client.started.isEmpty)
        #expect(model.shownStation == nil)
    }
}
