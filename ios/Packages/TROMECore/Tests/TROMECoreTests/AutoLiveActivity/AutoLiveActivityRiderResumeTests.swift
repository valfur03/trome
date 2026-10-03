import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    func snoozedAtAWithTheAppOpen(_ model: AutoLiveActivityModel, heldPositionAge: TimeInterval) async {
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await model.snooze(for: .oneHour)
        clock.advance(by: heldPositionAge)
    }

    func turnedOffAtAWithTheAppOpen(_ model: AutoLiveActivityModel, heldPositionAge: TimeInterval) async {
        automaticMode.setOn(false)
        await activate(model)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { locationService.position == Places.fiftyMetersFromA }
        clock.advance(by: heldPositionAge)
    }

    func turnOnTheAutomaticMode(in model: AutoLiveActivityModel) async {
        automaticMode.setOn(true)
        await model.automaticModeTurnedOn()
    }

    @Test(arguments: [10.0, 45.0])
    func cancellingTheSnoozeAtTheStationStartsItsLiveActivityAtOnce(heldPositionAge: TimeInterval) async {
        let model = makeModel()
        await snoozedAtAWithTheAppOpen(model, heldPositionAge: heldPositionAge)

        await model.cancelSnooze()

        #expect(automaticMode.mode == .turnedOn)
        #expect(model.shownStation == Places.stationA)
        #expect(client.started.count == 2)
        #expect(notifier.notified.isEmpty)
        #expect(model.cannotFindPosition == false)
    }

    @Test(arguments: [10.0, 45.0])
    func turningOnTheAutomaticModeAtTheStationStartsItsLiveActivityAtOnce(heldPositionAge: TimeInterval) async {
        let model = makeModel()
        await turnedOffAtAWithTheAppOpen(model, heldPositionAge: heldPositionAge)
        #expect(client.started.isEmpty)

        await turnOnTheAutomaticMode(in: model)

        #expect(model.shownStation == Places.stationA)
        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(notifier.notified.isEmpty)
        #expect(gps.currentFixRequestCount == (heldPositionAge > 15 ? 1 : 0))
    }

    @Test func cancellingTheSnoozeAwayFromEveryStationStartsNothingAndSaysNothing() async {
        let model = makeModel()
        await snoozedAtAWithTheAppOpen(model, heldPositionAge: 10)
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { locationService.position == Places.fourHundredMetersFromA }

        await model.cancelSnooze()

        #expect(automaticMode.mode == .turnedOn)
        #expect(client.started.count == 1)
        #expect(model.shownStation == nil)
        #expect(model.cannotFindPosition == false)
    }

    @Test func turningOnTheAutomaticModeWithNoUsablePositionSaysSoThenTheNextPositionStartsIt() async {
        let model = makeModel()
        await turnedOffAtAWithTheAppOpen(model, heldPositionAge: 121)
        gps.givesACurrentFix = false

        await turnOnTheAutomaticMode(in: model)
        #expect(model.cannotFindPosition)
        #expect(client.started.isEmpty)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.started.count == 1 }
        #expect(model.shownStation == Places.stationA)
        #expect(model.cannotFindPosition == false)
    }

    @Test func turningOnTheAutomaticModeWhileTheAppIsNotActiveStartsNothingAndAsksForNoPosition() async {
        let model = makeModel()
        await turnedOffAtAWithTheAppOpen(model, heldPositionAge: 45)
        model.setAppPhase(.background)

        await turnOnTheAutomaticMode(in: model)

        #expect(gps.currentFixRequestCount == 0)
        #expect(client.started.isEmpty)
        #expect(notifier.notified.isEmpty)
        #expect(model.cannotFindPosition == false)
    }

    @Test func theSnoozeStaysUntilThePositionComesThenEndsEvenIfTheAppLeftTheFront() async {
        let model = makeModel()
        await snoozedAtAWithTheAppOpen(model, heldPositionAge: 45)
        gps.holdsTheCurrentFixRequest = true

        let cancel = Task { await model.cancelSnooze() }
        await waitUntil { gps.currentFixRequestCount == 1 }
        #expect(automaticMode.mode != .turnedOn)
        model.setAppPhase(.background)
        gps.answerTheHeldRequests()
        await cancel.value

        #expect(automaticMode.mode == .turnedOn)
        #expect(client.started.count == 1)
        #expect(notifier.notified.isEmpty)
        #expect(model.cannotFindPosition == false)
    }

    @Test func cancellingThePauseWhileSnoozedEndsThePauseAndAsksForNoPosition() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 45)
        await model.snooze(for: .oneHour)

        await model.cancelPause()

        #expect(model.pausedStation == nil)
        #expect(gps.currentFixRequestCount == 0)
        #expect(client.started.count == 1)
    }

    @Test func cancellingTheSnoozeAtAPausedStationKeepsThePauseAndStartsNothing() async {
        let model = makeModel()
        await pausedAtAWithTheAppOpen(model, heldPositionAge: 10)
        await model.snooze(for: .oneHour)

        await model.cancelSnooze()

        #expect(model.pausedStation?.station == Places.stationA)
        #expect(client.started.count == 1)
        #expect(model.cannotFindPosition == false)
    }

    @Test func aResumeWhileALiveActivityShowsAsksForNoPositionAndChangesNothing() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        automaticMode.snooze(for: .oneHour)

        await model.cancelSnooze()

        #expect(automaticMode.mode == .turnedOn)
        #expect(gps.currentFixRequestCount == 0)
        #expect(client.started.count == 1)
        #expect(model.shownStation == Places.stationA)
    }
}
