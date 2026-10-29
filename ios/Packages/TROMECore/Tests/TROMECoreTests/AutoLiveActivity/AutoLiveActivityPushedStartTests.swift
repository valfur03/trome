import Foundation
import Testing
@testable import TROMECore

/// The Live Activity that the server's push started: the app follows it as one that it started itself, so that it
/// ends when the rider leaves or after 45 minutes, and the next station does not bring a second one.
extension AutoLiveActivityModelTests {
    /// The "left stop area" event of Le Parc on the outing of 2026-10-18 (17:08:16): the phone 328 m from the
    /// station point, ±25 m, 0 s old.
    static let leParcExit = Coordinate(48.80836, 2.486624)

    func pushedStartModel(catalog: StationCatalog = Places.catalog) -> AutoLiveActivityModel {
        makeModel(catalog: catalog, silentStart: silentStart(StubLiveActivityStarter(answer: .started)))
    }

    /// Apple's push brings the Live Activity: iOS shows it, and tells the running app.
    func pushLands(at station: Station) {
        client.isShowing = true
        client.shownContent = StationActivityAttributes.ContentState(station: station, trains: .loading, now: clock.now)
        removals.reportAppearance()
    }

    func arriveAtLeParc(_ model: AutoLiveActivityModel) async {
        let entered = RegionEvent.entered(regionId: "arrival:\(Self.leParc.id)")
        let fix = PositionFix(coordinate: Self.leParcEdge, accuracyMeters: 13, timestamp: clock.now)
        await model.handleRegionEvent(entered, lastKnownFix: fix)
    }

    func leaveLeParc(_ model: AutoLiveActivityModel) async {
        let left = RegionEvent.left(regionId: "stop:\(Self.leParc.id)")
        let fix = PositionFix(coordinate: Self.leParcExit, accuracyMeters: 25, timestamp: clock.now)
        await model.handleRegionEvent(left, lastKnownFix: fix)
    }

    var leParcCatalog: StationCatalog {
        StationCatalog(stations: [Self.leParc])
    }

    /// AC: the exit of the outing ends the Live Activity that the push started, with no alert, no pause, no snooze.
    @Test func theExitOfTheOutingEndsTheLiveActivityThatThePushStarted() async {
        let model = pushedStartModel(catalog: leParcCatalog)
        await arriveAtLeParc(model)
        pushLands(at: Self.leParc)
        #expect(model.shownStation == Self.leParc)
        #expect(keeper.isKeeping)

        await leaveLeParc(model)

        #expect(client.endCount == 1)
        #expect(model.shownStation == nil)
        #expect(!keeper.isKeeping)
        #expect(notifier.notified.isEmpty)
        #expect(model.pausedStation == nil)
        #expect(automaticMode.mode == .turnedOn)
        #expect(wakeLog.entries.contains { $0.text == "Live Activity ended: 328 m from Le Parc de Saint-Maur" })
    }

    /// The outing: iOS never ran the app between the ask and the exit, so the app first sees the Live Activity
    /// in the process that iOS starts for the exit.
    @Test func theExitEndsItAlsoWhenTheAppFirstSeesItAtTheExit() async {
        let asking = pushedStartModel(catalog: leParcCatalog)
        await arriveAtLeParc(asking)
        withExtendedLifetime(asking) {}
        client.isShowing = true

        let woken = pushedStartModel(catalog: leParcCatalog)
        await leaveLeParc(woken)

        #expect(client.endCount == 1)
        #expect(woken.shownStation == nil)
        #expect(notifier.notified.isEmpty)
    }

    /// AC: the 45 minutes count from the server's answer, also when the app sees the Live Activity later.
    @Test func the45MinutesEndItWhenNoExitComes() async {
        let asking = pushedStartModel()
        await wake(asking, at: Places.fiftyMetersFromA)
        withExtendedLifetime(asking) {}
        client.isShowing = true
        clock.advance(by: AutoLiveActivityRules.defaultMaximumDuration)

        let woken = pushedStartModel()
        await wake(woken, at: Places.fiftyMetersFromA)

        #expect(client.endCount == 1)
        #expect(woken.shownStation == nil)
        #expect(wakeLog.entries.contains { $0.text == "Live Activity ended: 45 min after it started" })
    }

    @Test func theTimerOfThe45MinutesEndsItWhileTheAppRuns() async {
        let model = pushedStartModel()
        await wake(model, at: Places.fiftyMetersFromA)
        clock.letTimersFire()
        pushLands(at: Places.stationA)

        await waitUntil { client.endCount == 1 && !keeper.isKeeping }

        #expect(client.endCount == 1)
        #expect(model.shownStation == nil)
    }

    @Test(.timeLimit(.minutes(1))) func followsAPushThatLandsDuringTheAsk() async {
        let starter = StubLiveActivityStarter(answer: nil)
        let model = makeModel(silentStart: silentStart(starter))

        let wake = Task { await wake(model, at: Places.fiftyMetersFromA) }
        await waitUntil { starter.asks.count == 1 }
        client.isShowing = true
        starter.answer(with: .started)
        await wake.value

        #expect(model.shownStation == Places.stationA)
        #expect(keeper.isKeeping)
        #expect(silentStartLines.last == "Follows the Live Activity that the server started: Station A")
    }

    /// Review of the silent start, case 1: a Live Activity that the push started listens to the channel of its
    /// station, so a switch would show the trains of the first station again at its next update.
    @Test func theNextStationEndsItAndAsksTheServerForItsOwn() async {
        let starter = StubLiveActivityStarter(answer: .started)
        let model = makeModel(silentStart: silentStart(starter))
        await wake(model, at: Places.fiftyMetersFromA)
        pushLands(at: Places.stationA)

        await wake(model, at: Places.atB)

        #expect(client.endCount == 1)
        #expect(client.updates.allSatisfy { $0.stationName == "Station A" })
        #expect(starter.asks.map(\.stationId) == ["a", "b"])
        #expect(notifier.notified.isEmpty)
        #expect(wakeLog.entries.contains {
            $0.text == "Live Activity ended: the server started it for another station than Station B"
        })
    }

    @Test func theNextStationWithTheAppOpenEndsItAndStartsTheAppsOwn() async {
        let model = pushedStartModel()
        await wake(model, at: Places.fiftyMetersFromA)
        pushLands(at: Places.stationA)
        await activate(model)

        gps.report(Places.atB)
        await waitUntil { client.started.count == 1 }

        #expect(client.endCount == 1)
        #expect(client.started.map(\.stationName) == ["Station B"])
        #expect(model.shownStation == Places.stationB)
    }

    /// Review of the silent start, case 2: the app open at the station when the server answers "started" waits
    /// for the push, rather than starting a second Live Activity.
    @Test func theAppOpenAtTheStationWaitsForThePush() async {
        let model = pushedStartModel()
        await wake(model, at: Places.fiftyMetersFromA)
        await activate(model)
        gps.report(Places.fiftyMetersFromA)
        await waitUntil { wakeLog.entries.contains { $0.text == sameArrivalLine(at: Places.stationA) } }
        #expect(client.started.isEmpty)

        pushLands(at: Places.stationA)

        #expect(client.started.isEmpty)
        #expect(model.shownStation == Places.stationA)
    }

    @Test func theAppOpenAtTheStationStartsItsOwnWhenThePushDoesNotCome() async {
        let model = pushedStartModel()
        await wake(model, at: Places.fiftyMetersFromA)
        await activate(model)
        clock.advance(by: PushedStart.landingWait)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.started.count == 1 }

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
    }

    /// A Live Activity that the rider started by hand is not taken for the push's.
    @Test func followsNoLiveActivityWithNoStartOfTheServer() async {
        let model = makeModel()
        client.isShowing = true
        removals.reportAppearance()

        #expect(model.shownStation == nil)
        #expect(!keeper.isKeeping)
    }

    @Test func theRiderWhoSwipesItAwayPausesTheStationAsForTheAppsOwn() async {
        let model = pushedStartModel()
        await wake(model, at: Places.fiftyMetersFromA)
        pushLands(at: Places.stationA)

        swipeAway()

        #expect(model.pausedStation?.station == Places.stationA)
        #expect(automaticMode.mode == .turnedOn)
    }

    /// An update of the app keeps the Live Activity that the version before it showed and followed.
    @Test func readsTheStateThatAnEarlierVersionSaved() throws {
        let saved = Data(#"{"shown":{"stationId":"a","startedAt":0,"hasBeenNear":true},"arrivalStationId":"a"}"#.utf8)

        let state = try JSONDecoder().decode(AutoLiveActivityState.self, from: saved)

        #expect(state.shown?.stationId == "a")
        #expect(state.shown?.isStartedByThePush == false)
        #expect(state.pushedStart == nil)
    }
}
