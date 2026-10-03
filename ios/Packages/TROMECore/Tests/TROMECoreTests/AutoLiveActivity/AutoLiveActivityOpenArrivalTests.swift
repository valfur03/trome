import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    func notifiedInTheBackground(in model: AutoLiveActivityModel) async {
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !notifier.notified.isEmpty }
        #expect(client.started.isEmpty)
    }

    func openTheApp(_ model: AutoLiveActivityModel, after seconds: TimeInterval) async {
        clock.advance(by: seconds)
        await activate(model)
    }

    @Test func openingTheAppAtTheStationOfANotifiedArrivalStartsItsLiveActivity() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)

        await openTheApp(model, after: 30)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
        #expect(notifier.notified == [Places.stationA])
        #expect(notifier.withdrawCount == 1)
        #expect(gps.currentFixRequestCount == 1)
        #expect(model.cannotFindPosition == false)
    }

    @Test func openingTheAppAtOnceUsesTheHeldPositionWithNoRequest() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)

        await openTheApp(model, after: 5)

        #expect(model.shownStation == Places.stationA)
        #expect(gps.currentFixRequestCount == 0)
    }

    @Test func openingTheAppWithNoAnswerFromIOSUsesAHeldPositionOfAtMost2Minutes() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.givesACurrentFix = false

        await openTheApp(model, after: 110)

        #expect(model.shownStation == Places.stationA)
    }

    @Test func aNotifiedArrivalStillStartsAfterARelaunchOfTheApp() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)

        let relaunched = makeModel()
        await openTheApp(relaunched, after: 30)

        #expect(relaunched.shownStation == Places.stationA)
        #expect(client.started.count == 1)
        withExtendedLifetime(model) {}
    }

    @Test func withNotificationsRefusedOpeningTheAppAtTheStationStartsTheLiveActivity() async {
        notifier.isRefusedByTheRider = true
        let model = makeModel()
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }
        #expect(notifier.notified.isEmpty)

        await openTheApp(model, after: 30)

        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 1)
    }

    @Test func openingTheAppAfterLeavingTheStationStartsNothing() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { notifier.withdrawCount == 1 }

        await openTheApp(model, after: 30)

        #expect(client.started.isEmpty)
        #expect(gps.currentFixRequestCount == 0)
    }

    @Test func openingTheAppFarFromTheStationWithNoPositionSeenOnTheWayStartsNothingAndSaysNothing() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.stopReporting()
        gps.report(Places.fourHundredMetersFromA)

        await openTheApp(model, after: 30)

        #expect(gps.currentFixRequestCount == 1)
        #expect(client.started.isEmpty)
        #expect(model.cannotFindPosition == false)
    }

    @Test func openingTheAppTwiceStartsOneLiveActivity() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        await openTheApp(model, after: 30)
        model.setAppPhase(.background)

        await openTheApp(model, after: 30)

        #expect(client.started.count == 1)
        #expect(notifier.notified.count == 1)
    }

    @Test func openingTheAppAfterATapOnTheNotificationStartsOneLiveActivity() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)

        await model.notificationTapped(stationId: "a")
        await openTheApp(model, after: 30)

        #expect(client.started.count == 1)
        #expect(gps.currentFixRequestCount == 0)
    }

    @Test(arguments: [SnoozeDuration.thirtyMinutes, .oneHour])
    func openingTheAppAfterASnoozeStartsNothingEvenOnceTheSnoozeIsOver(duration: SnoozeDuration) async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        await model.snooze(for: duration)

        await openTheApp(model, after: 30)
        model.setAppPhase(.background)
        await openTheApp(model, after: 2 * 60 * 60)

        #expect(client.started.isEmpty)
        #expect(gps.currentFixRequestCount == 0)
    }

    @Test func openingTheAppWithTheAutomaticModeOffStartsNothing() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        automaticMode.setOn(false)

        await openTheApp(model, after: 30)

        #expect(client.started.isEmpty)
        #expect(gps.currentFixRequestCount == 0)
    }

    @Test func openingTheAppAgainAfterTheLiveActivityOfThatArrivalWasSwipedStartsNothing() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        await openTheApp(model, after: 30)
        swipeAway()
        model.setAppPhase(.background)

        await openTheApp(model, after: 30)

        #expect(client.started.count == 1)
        #expect(model.pausedStation?.station == Places.stationA)
    }

    @Test func openingTheAppAgainAfterTheTimeLimitOfThatArrivalStartsNothing() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        await openTheApp(model, after: 30)
        model.setAppPhase(.background)

        await openTheApp(model, after: AutoLiveActivityRules.defaultMaximumDuration)

        #expect(client.endCount == 1)
        #expect(client.started.count == 1)
    }

    @Test func aNewArrivalReplacesTheOpenOne() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.report(Places.atB)
        await waitUntil { notifier.notified.count == 2 }

        await openTheApp(model, after: 30)

        #expect(client.started.map(\.stationName) == ["Station B"])
    }

    @Test func openingTheAppWithAnOldPositionAndNoAnswerFromIOSStartsNothingAndSaysSo() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.givesACurrentFix = false

        await openTheApp(model, after: 121)

        #expect(client.started.isEmpty)
        #expect(model.cannotFindPosition)
    }

    @Test func openingTheAppWithAnImprecisePositionStartsNothingAndSaysSo() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.report(PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 300, timestamp: clock.now))
        await waitUntil { locationService.fix?.accuracyMeters == 300 }
        gps.givesACurrentFix = false

        await openTheApp(model, after: 5)

        #expect(client.started.isEmpty)
        #expect(model.cannotFindPosition)
    }

    @Test func theLiveActivityStartsWhenAUsablePositionArrivesAfterTheNoPositionLine() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.givesACurrentFix = false
        await openTheApp(model, after: 121)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.isShowing }

        #expect(model.shownStation == Places.stationA)
        #expect(model.cannotFindPosition == false)
        #expect(notifier.notified.count == 1)
    }

    @Test func aPositionThatStartsTheLiveActivityDuringTheWaitForIOSLeavesNoNoPositionLine() async {
        let model = makeModel()
        await notifiedInTheBackground(in: model)
        gps.holdsTheCurrentFixRequest = true
        clock.advance(by: 121)
        model.setAppPhase(.active)

        let opening = Task { await model.appDidBecomeActive() }
        await waitUntil { gps.currentFixRequestCount == 1 }
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.isShowing }
        gps.givesACurrentFix = false
        gps.answerTheHeldRequests()
        await opening.value

        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition == false)
    }

    @Test func openingTheAppWithNoOpenArrivalAsksIOSForNothing() async {
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }

        await openTheApp(model, after: 30)

        #expect(gps.currentFixRequestCount == 0)
        #expect(model.cannotFindPosition == false)
    }
}
