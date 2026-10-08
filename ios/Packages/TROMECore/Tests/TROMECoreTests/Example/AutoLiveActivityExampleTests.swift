import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    static let cupertino = Coordinate(37.3349, -122.0090)

    func catalogWithChatelet() throws -> StationCatalog {
        let bundled = try StationCatalog.bundled()
        let chatelet = try #require(bundled.station(withId: ExampleTimetable.stationId))
        return StationCatalog(stations: Places.catalog.stations + bundled.hubStations(of: chatelet))
    }

    func showingTheExample() async throws -> AutoLiveActivityModel {
        let model = makeModel(catalog: try catalogWithChatelet())
        await activate(model)
        await model.exampleTapped()
        return model
    }

    @Test(arguments: [LocationAuthorization.denied, .notDetermined, .authorized])
    func aTapShowsChateletWithSampleTimesFarFromParisWithNoTrainCall(location: LocationAuthorization) async throws {
        permission.authorization = location
        notifier.isRefusedByTheRider = true
        let model = makeModel(catalog: try catalogWithChatelet())
        await activate(model)
        gps.report(Self.cupertino)

        await model.exampleTapped()

        #expect(client.started.map(\.stationName) == ["Châtelet"])
        #expect(client.started.first?.trains.linesPage?.allLines.count == 8)
        #expect(model.showsExample)
        #expect(model.shownStation == nil)
        #expect(provider.callCount == 0)
        #expect(keeper.isKeeping == false)
    }

    @Test func aSecondTapRestartsTheExampleWithFreshTimes() async throws {
        let model = try await showingTheExample()
        clock.advance(by: 300)

        await model.exampleTapped()

        #expect(client.started.count == 1)
        #expect(client.updates.last?.updatedAt == clock.now)
        #expect(AutoLiveActivityStore(storage: storage).load().exampleStartedAt == clock.now)
    }

    @Test func aSwipeEndsTheExampleWithNoPause() async throws {
        let model = try await showingTheExample()

        swipeAway()
        await waitUntil { !model.showsExample }

        #expect(model.showsExample == false)
        #expect(model.pausedStation == nil)
        #expect(AutoLiveActivityStore(storage: storage).load().exampleStartedAt == nil)
    }

    @Test func aSnoozeButtonOfTheLockScreenEndsTheExampleAndSnoozesNothing() async throws {
        let model = try await showingTheExample()

        await model.snoozeTappedOnTheLockScreen(for: .oneHour)

        #expect(client.isShowing == false)
        #expect(model.showsExample == false)
        #expect(automaticMode.mode == .turnedOn)
    }

    @Test func aRealArrivalReplacesTheExample() async throws {
        let model = try await showingTheExample()

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { model.shownStation != nil && keeper.isKeeping }

        #expect(client.started.count == 1)
        #expect(client.updates.last?.stationName == "Station A")
        #expect(model.shownStation == Places.stationA)
        #expect(model.showsExample == false)
    }

    @Test func aTapWhileRealTrainsShowStartsNothing() async throws {
        let model = makeModel(catalog: try catalogWithChatelet())
        await arrive(at: Places.fiftyMetersFromA, in: model)
        let updateCount = client.updates.count

        await model.exampleTapped()

        #expect(model.showsExample == false)
        #expect(model.shownStation == Places.stationA)
        #expect(client.updates.dropFirst(updateCount).allSatisfy { $0.stationName == "Station A" })
    }

    @Test func aTapWithLiveActivitiesTurnedOffStartsNothingAndSaysWhy() async throws {
        client.startError = StationLiveActivityError.turnedOff
        let model = makeModel(catalog: try catalogWithChatelet())
        await activate(model)

        await model.exampleTapped()

        #expect(client.isShowing == false)
        #expect(model.showsExample == false)
        #expect(model.liveActivity.startError == .turnedOff)
    }

    @Test func theExampleEndsAfterTenMinutesWhenTheAppRunsAgain() async throws {
        let model = try await showingTheExample()
        model.setAppPhase(.background)
        clock.advance(by: 600)

        await activate(model)
        await waitUntil { !client.isShowing }

        #expect(client.endCount == 1)
        #expect(model.showsExample == false)
        #expect(automaticMode.mode == .turnedOn)
        #expect(model.pausedStation == nil)
        #expect(AutoLiveActivityStore(storage: storage).load().exampleStartedAt == nil)
    }

    @Test func nothingOfTheExampleIsKeptOnceIOSNoLongerShowsIt() async throws {
        _ = try await showingTheExample()
        client.isShowing = false

        let relaunched = makeModel(catalog: try catalogWithChatelet())

        #expect(relaunched.showsExample == false)
        #expect(relaunched.state.exampleStartedAt == nil)
    }

    @Test func aRelaunchWhileTheExampleShowsKeepsItGoing() async throws {
        _ = try await showingTheExample()

        let relaunched = makeModel(catalog: try catalogWithChatelet())

        #expect(relaunched.showsExample)
        #expect(keeper.isKeeping == false)
    }

    // The return to the front: what the lock screen shows once the phone locks again.

    func lockedScreenAfterTheFront(of model: AutoLiveActivityModel) async -> StationActivityAttributes.ContentState? {
        await activate(model)
        model.setAppPhase(.background)
        return client.shownContent
    }

    func secondsOfCountdown(on content: StationActivityAttributes.ContentState?) -> TimeInterval {
        guard let content, !content.isMarkedStale, let staleDate = content.staleDate else { return 0 }
        return staleDate.timeIntervalSince(clock.now)
    }

    @Test(arguments: [60.0, 330, 540])
    func theFrontRestartsTheExampleForFiveMoreMinutes(secondsAfterTheTap seconds: TimeInterval) async throws {
        let model = try await showingTheExample()
        model.setAppPhase(.background)
        clock.advance(by: seconds)

        let locked = await lockedScreenAfterTheFront(of: model)

        #expect(locked?.stationName == "Châtelet")
        #expect(secondsOfCountdown(on: locked) >= 300)
        #expect(client.started.count == 1)
        #expect(AutoLiveActivityStore(storage: storage).load().exampleStartedAt == clock.now)
    }

    @Test func theTenMinutesCountFromTheLastReturnToTheFront() async throws {
        let model = try await showingTheExample()
        model.setAppPhase(.background)
        clock.advance(by: 300)
        _ = await lockedScreenAfterTheFront(of: model)
        clock.advance(by: 599)

        let locked = await lockedScreenAfterTheFront(of: model)
        #expect(secondsOfCountdown(on: locked) >= 300)
        clock.advance(by: 600)
        await activate(model)
        await waitUntil { !client.isShowing }

        #expect(client.endCount == 1)
        #expect(model.showsExample == false)
    }

    @Test func theFrontAfterASwipeStartsNothing() async throws {
        let model = try await showingTheExample()
        model.setAppPhase(.background)
        let updateCount = client.updates.count
        client.isShowing = false

        await activate(model)

        #expect(client.started.count == 1)
        #expect(client.updates.count == updateCount)
        #expect(model.showsExample == false)
        #expect(model.pausedStation == nil)
    }

    @Test func theFrontAfterASnoozeButtonStartsNothing() async throws {
        let model = try await showingTheExample()
        model.setAppPhase(.background)
        await model.snoozeTappedOnTheLockScreen(for: .oneHour)
        clock.advance(by: 60)

        await activate(model)

        #expect(client.isShowing == false)
        #expect(client.started.count == 1)
        #expect(model.showsExample == false)
    }

    @Test func theFrontAfterARealArrivalKeepsTheRealTrains() async throws {
        let model = try await showingTheExample()
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { model.shownStation != nil && keeper.isKeeping }
        model.setAppPhase(.background)
        clock.advance(by: 60)

        await activate(model)

        #expect(client.shownContent?.stationName == "Station A")
        #expect(model.showsExample == false)
        #expect(AutoLiveActivityStore(storage: storage).load().exampleStartedAt == nil)
    }
}
