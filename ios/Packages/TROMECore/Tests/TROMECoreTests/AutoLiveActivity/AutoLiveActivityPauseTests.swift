import Foundation
import Testing
@testable import TROMECore

@MainActor
final class StubLiveActivityRemovals: LiveActivityRemovalWatcher {
    private var onRemoval: (@MainActor (LiveActivityRemoval) -> Void)?

    func watchRemovals(_ onRemoval: @escaping @MainActor (LiveActivityRemoval) -> Void) {
        self.onRemoval = onRemoval
    }

    func report(endedByTheApp: Bool = false, activitiesAreEnabled: Bool = true) {
        onRemoval?(LiveActivityRemoval(endedByTheApp: endedByTheApp, activitiesAreEnabled: activitiesAreEnabled))
    }
}

extension AutoLiveActivityModelTests {
    func swipeAway(activitiesAreEnabled: Bool = true) {
        client.isShowing = false
        removals.report(activitiesAreEnabled: activitiesAreEnabled)
    }

    func pausedAtA(_ model: AutoLiveActivityModel) async {
        await arrive(at: Places.fiftyMetersFromA, in: model)
        swipeAway()
        model.setAppPhase(.background)
    }

    @Test func aSwipePausesItsStationForOneHourAndStopsTheBackgroundLocation() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        swipeAway()

        let end = clock.now.addingTimeInterval(3_600)
        #expect(model.pausedStation == PausedStation(station: Places.stationA, end: end))
        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func aSwipeThatTheAppSeesFirstAsAGoneLiveActivityStillPauses() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        client.isShowing = false
        await activate(model)
        #expect(model.shownStation == nil)
        removals.report()

        #expect(model.pausedStation?.station == Places.stationA)
    }

    @Test(arguments: [OwnEnd.byHand, .snooze, .farFromTheStation, .timeLimit])
    func theAppsOwnEndSetsNoPause(end: OwnEnd) async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        switch end {
        case .byHand:
            await model.stopByHand()
        case .snooze:
            await model.snooze(for: .thirtyMinutes)
        case .farFromTheStation:
            await wake(model, at: Places.fourHundredMetersFromA)
        case .timeLimit:
            clock.advance(by: AutoLiveActivityRules.defaultMaximumDuration)
            await wake(model, at: Places.fiftyMetersFromA)
        }
        #expect(client.endCount == 1)
        removals.report(endedByTheApp: true)
        removals.report(endedByTheApp: false)

        #expect(model.pausedStation == nil)
    }

    @Test func aSwitchToAnotherStationSetsNoPause() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await wake(model, at: Places.atB)
        removals.report(endedByTheApp: true)

        #expect(model.shownStation == Places.stationB)
        #expect(model.pausedStation == nil)
    }

    @Test func turningOffLiveActivitiesInSettingsSetsNoPause() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        swipeAway(activitiesAreEnabled: false)

        #expect(model.pausedStation == nil)
        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func aLiveActivityThatIOSEndsAfterEightHoursSetsNoPause() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        clock.advance(by: 8 * 3_600)
        swipeAway()

        #expect(model.pausedStation == nil)
    }

    @Test func aLaunchThatFindsTheLiveActivityGoneSetsNoPause() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        client.isShowing = false

        let relaunched = makeModel()
        removals.report()

        #expect(relaunched.shownStation == nil)
        #expect(relaunched.pausedStation == nil)
        withExtendedLifetime(model) {}
    }

    @Test func thePauseSurvivesARelaunch() async {
        let model = makeModel()
        await pausedAtA(model)

        let relaunched = makeModel()

        #expect(relaunched.pausedStation == model.pausedStation)
        #expect(relaunched.pausedStation?.station == Places.stationA)
    }

    @Test func neitherNotifiesNorStartsAtThePausedStationEvenAfterLeavingAndComingBack() async {
        let model = makeModel()
        await pausedAtA(model)

        await wake(model, at: Places.fourHundredMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)
        await activate(model)
        await wake(model, at: Places.fourHundredMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified.isEmpty)
        #expect(client.started.count == 1)
        #expect(model.pausedStation?.station == Places.stationA)
    }

    @Test func theStationWorksAgainAfterTheHour() async {
        let model = makeModel()
        await pausedAtA(model)

        clock.advance(by: 3_600)
        await wake(model, at: Places.fourHundredMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
        #expect(model.pausedStation == nil)
    }

    @Test func thePauseLineGoesAwayWhenTheHourIsOver() async {
        let model = makeModel()
        await pausedAtA(model)

        clock.letTimersFire()
        await waitUntil { model.pausedStation == nil }

        #expect(model.pausedStation == nil)
    }

    @Test func anotherStationNotifiesInTheBackgroundAndStartsWithTheAppOpenDuringThePause() async {
        let model = makeModel()
        await pausedAtA(model)

        await wake(model, at: Places.atB)
        #expect(notifier.notified == [Places.stationB])
        await wake(model, at: Places.fourHundredMetersFromA)
        await activate(model)
        await wake(model, at: Places.atB)

        #expect(client.started.map(\.stationName) == ["Station A", "Station B"])
        #expect(model.shownStation == Places.stationB)
        #expect(model.pausedStation?.station == Places.stationA)
    }

    @Test func aLiveActivityOfAnotherStationDoesNotSwitchToThePausedStation() async {
        let model = makeModel()
        await pausedAtA(model)
        await activate(model)
        await wake(model, at: Places.atB)

        await wake(model, at: Coordinate(48.8500, 2.3514))

        #expect(model.shownStation == Places.stationB)
        #expect(client.shownContent?.stationName == "Station B")
    }

    @Test func aSwipeAtAnotherStationReplacesThePause() async {
        let model = makeModel()
        await pausedAtA(model)
        clock.advance(by: 600)
        await activate(model)
        await wake(model, at: Places.atB)

        swipeAway()

        let end = clock.now.addingTimeInterval(3_600)
        #expect(model.pausedStation == PausedStation(station: Places.stationB, end: end))
        await wake(model, at: Places.fourHundredMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func aStartByHandAtThePausedStationEndsThePause() async {
        let model = makeModel()
        await pausedAtA(model)

        await model.startByHand(Places.stationB)
        #expect(model.pausedStation?.station == Places.stationA)
        await model.startByHand(Places.stationA)

        #expect(model.pausedStation == nil)
    }

    @Test func aTapOnTheArrivalNotificationOfThePausedStationEndsThePause() async {
        let model = makeModel()
        await pausedAtA(model)

        await model.notificationTapped(stationId: "a")
        await activate(model)

        #expect(model.pausedStation == nil)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func aSnoozeKeepsThePauseAndItsEnd() async {
        let model = makeModel()
        await pausedAtA(model)
        let pause = model.pausedStation

        await model.snooze(for: .restOfToday)
        automaticMode.cancelSnooze()

        #expect(model.pausedStation == pause)
    }

    @Test func cancellingThePauseStartsTheLiveActivityAtOnceWhenTheRiderIsAtTheStationWithTheAppOpen() async {
        let model = makeModel()
        await pausedAtA(model)
        await activate(model)

        await model.cancelPause()

        #expect(model.pausedStation == nil)
        #expect(client.started.count == 2)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func cancellingThePauseAwayFromTheStationLetsTheNextArrivalWork() async {
        let model = makeModel()
        await pausedAtA(model)
        await wake(model, at: Places.fourHundredMetersFromA)

        await model.cancelPause()
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(model.pausedStation == nil)
        #expect(notifier.notified == [Places.stationA])
    }
}

enum OwnEnd: CaseIterable, Sendable {
    case byHand
    case snooze
    case farFromTheStation
    case timeLimit
}
