import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    func turnOffLiveActivities() {
        client.areActivitiesEnabled = false
        client.startError = StationLiveActivityError.turnedOff
    }

    func turnOnLiveActivities() {
        client.areActivitiesEnabled = true
        client.startError = nil
    }

    func refusedOnTheLockScreenAtA(_ model: AutoLiveActivityModel) async {
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
        turnOffLiveActivities()
        swipeAway(activitiesAreEnabled: false)
    }

    func comeBackFromSettings(to model: AutoLiveActivityModel) async {
        model.setAppPhase(.background)
        turnOnLiveActivities()
        await openTheApp(model, after: 30)
    }

    @Test func afterNotAllowingLiveActivitiesTheAppSaysSoAtOnceAndStartsNothing() async {
        let model = makeModel()
        await refusedOnTheLockScreenAtA(model)

        await openTheApp(model, after: 30)

        #expect(model.liveActivityProblem == .turnedOff)
        #expect(model.shownStation == nil)
        #expect(model.pausedStation == nil)
        #expect(client.started.count == 1)
        #expect(gps.currentFixRequestCount == 0)
    }

    @Test func turningLiveActivitiesOnAgainAtTheStationStartsItsLiveActivityAtOnceWithNoNotification() async {
        let model = makeModel()
        await refusedOnTheLockScreenAtA(model)
        await openTheApp(model, after: 30)

        await comeBackFromSettings(to: model)

        #expect(model.liveActivityProblem == nil)
        #expect(model.shownStation == Places.stationA)
        #expect(client.started.map(\.stationName) == ["Station A", "Station A"])
        #expect(notifier.notified.isEmpty)
    }

    @Test func turningLiveActivitiesOnAgainAfterARelaunchAtTheStationStartsItsLiveActivity() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
        turnOffLiveActivities()
        client.isShowing = false

        let relaunched = makeModel()
        await comeBackFromSettings(to: relaunched)

        #expect(relaunched.shownStation == Places.stationA)
        #expect(client.started.count == 2)
        withExtendedLifetime(model) {}
    }

    @Test func turningLiveActivitiesOnAgainAwayFromEveryStationStartsNothingAndSaysNothing() async {
        let model = makeModel()
        await refusedOnTheLockScreenAtA(model)
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { locationService.position == Places.fourHundredMetersFromA }

        await comeBackFromSettings(to: model)

        #expect(model.liveActivityProblem == nil)
        #expect(model.shownStation == nil)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition == false)
    }

    @Test func anArrivalWithTheAppOpenAndLiveActivitiesOffSaysSoAndStartsOnceTheyAreOn() async {
        turnOffLiveActivities()
        let model = makeModel()
        await activate(model)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { locationService.position == Places.fiftyMetersFromA }
        #expect(model.liveActivityProblem == .turnedOff)
        #expect(client.started.isEmpty)

        await comeBackFromSettings(to: model)

        #expect(model.shownStation == Places.stationA)
        #expect(notifier.notified.isEmpty)
    }

    @Test func theLineShowsAwayFromEveryStationOnlyWhileTheAutomaticModeIsOnAndLiveActivitiesAreOff() async {
        turnOffLiveActivities()
        let model = makeModel()
        await activate(model)
        #expect(model.liveActivityProblem == .turnedOff)

        automaticMode.snooze(for: .oneHour)
        #expect(model.liveActivityProblem == .turnedOff)

        automaticMode.setOn(false)
        #expect(model.liveActivityProblem == nil)

        automaticMode.setOn(true)
        await comeBackFromSettings(to: model)
        #expect(model.liveActivityProblem == nil)
    }

    @Test(arguments: [AppPhase.active, .background])
    func turningTheAutomaticModeOffEndsTheShownLiveActivityWithNoPause(appPhase: AppPhase) async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(appPhase)

        automaticMode.setOn(false)
        await waitUntil { client.endCount == 1 && !keeper.isKeeping }

        #expect(client.endCount == 1)
        #expect(client.isShowing == false)
        #expect(model.shownStation == nil)
        #expect(model.pausedStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func turningTheAutomaticModeOnAgainAtTheStationShowsTheLiveActivityAgain() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        automaticMode.setOn(false)
        await waitUntil { client.endCount == 1 }

        await turnOnTheAutomaticMode(in: model)

        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 2)
        #expect(notifier.notified.isEmpty)
    }
}
