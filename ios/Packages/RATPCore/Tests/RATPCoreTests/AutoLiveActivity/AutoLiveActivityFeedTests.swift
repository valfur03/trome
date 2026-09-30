import Foundation
import Testing
@testable import RATPCore

extension AutoLiveActivityModelTests {
    @Test func feedsTheLiveActivityAgainWhenRelaunchedWhileItShows() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { !client.updates.isEmpty }
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.launchDelay)
        let relaunched = makeModel()
        await waitUntil { provider.callCount > callCount }

        #expect(provider.callCount > callCount)
        withExtendedLifetime((model, relaunched)) {}
    }

    @Test func feedsTheLiveActivitySoonWhenIOSStartsTheAppInTheBackgroundWhileItShows() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { !client.updates.isEmpty }
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.launchDelay)
        let startedInTheBackground = makeModel()
        startedInTheBackground.setAppActive(false)
        await waitUntil { provider.callCount > callCount }

        #expect(provider.callCount > callCount)
        withExtendedLifetime((model, startedInTheBackground)) {}
    }

    @Test func asksOnceForTheTrainsWhenRelaunchedOnScreenWhileItShows() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { !client.updates.isEmpty }
        let callCount = provider.callCount

        let relaunched = makeModel()
        try? await Task.sleep(for: .milliseconds(50))
        await activate(relaunched)
        await waitUntil { provider.callCount > callCount }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(provider.callCount == callCount + 1)
        withExtendedLifetime(model) {}
    }

    @Test func feedsTheLiveActivityWithTheTrainsOfItsOwnStation() async {
        provider.answer(.failure(.unreachable), for: Places.stationA)
        let model = makeModel()

        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.updates.contains { $0.trains == .noData } }

        #expect(client.updates.last?.stationName == "Station A")
        #expect(client.updates.last?.trains == .noData)
    }

    @Test func keepsTheShownTrainsWhenARefreshFailsInTheBackground() async {
        let line12 = TransitLine(mode: .metro, name: "12")
        let station = Station(id: "m", name: "Station M", coordinate: Coordinate(48.8600, 2.3600), lines: [line12])
        provider.answer(.success([
            Departure(line: line12, destination: "Mairie d'Issy", time: clock.now.addingTimeInterval(300))
        ]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { !$0.shownTrains.isEmpty } }
        model.setAppActive(false)
        provider.answer(.failure(.unreachable), for: station)
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount > callCount }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(provider.callCount > callCount)
        #expect(client.shownContent?.trains != .noData)
        #expect(client.shownContent?.shownTrains.isEmpty == false)
    }

    @Test func stopsAskingButKeepsTheShownTrainsOnceTheKeyIsRejectedInTheBackground() async {
        let line12 = TransitLine(mode: .metro, name: "12")
        let station = Station(id: "m", name: "Station M", coordinate: Coordinate(48.8600, 2.3600), lines: [line12])
        provider.answer(.success([
            Departure(line: line12, destination: "Mairie d'Issy", time: clock.now.addingTimeInterval(300))
        ]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { !$0.shownTrains.isEmpty } }
        model.setAppActive(false)
        provider.answer(.failure(.keyRejected), for: station)
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount == callCount + 1 }
        await waitUntil { provider.callCount > callCount + 1 }

        #expect(provider.callCount == callCount + 1)
        #expect(client.shownContent?.shownTrains.isEmpty == false)
    }

    @Test func feedsTheLiveActivityItselfOnceTheScreenStopsUpdatingItsStation() async {
        let model = makeModel()
        let screen = Task { await screenTrains.keepUpdated(for: Places.stationA) }
        await waitUntil { provider.callCount == 1 }
        await arrive(at: Places.fiftyMetersFromA, in: model)
        #expect(provider.callCount == 1)

        screen.cancel()
        await waitUntil { provider.callCount == 2 }

        #expect(provider.callCount == 2)
    }

    @Test func keepsFeedingTheLiveActivityWhileTheAppIsInTheBackground() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppActive(false)
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount >= callCount + 2 }

        #expect(provider.callCount >= callCount + 2)
        #expect(client.isShowing)
    }

    @Test func getsTheFirstTrainsAtOnceWhenTheAppLeavesTheScreenDuringTheFirstLoad() async {
        provider.holdAnswers()
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { provider.callCount == 1 }
        let start = clock.now

        model.setAppActive(false)
        provider.releaseAnswers()
        await waitUntil { client.updates.last?.hasTrains ?? false }

        #expect(client.updates.last?.stationName == "Station A")
        #expect(client.updates.last?.hasTrains == true)
        #expect(clock.now == start)
    }

    @Test func getsTheTrainsOfTheNewStationAtOnceWhenTheAppLeavesTheScreenDuringTheLoadOfASwitch() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.updates.last?.hasTrains ?? false }
        provider.holdAnswers()
        gps.report(Places.atB)
        await waitUntil { provider.askedStationIds.last == ["b"] }
        let start = clock.now

        model.setAppActive(false)
        provider.releaseAnswers()
        await waitUntil { client.updates.last?.stationName == "Station B" && client.updates.last?.hasTrains == true }

        #expect(client.updates.last?.stationName == "Station B")
        #expect(client.updates.last?.hasTrains == true)
        #expect(clock.now == start)
    }

    @Test func getsTheFirstTrainsAtOnceWhenTheScreenStopsLoadingThemAsTheAppLeavesTheScreen() async {
        provider.holdAnswers()
        let model = makeModel()
        let screen = Task { await screenTrains.keepUpdated(for: Places.stationA) }
        await waitUntil { provider.callCount == 1 }
        await arrive(at: Places.fiftyMetersFromA, in: model)
        let start = clock.now

        screen.cancel()
        model.setAppActive(false)
        provider.releaseAnswers()
        await waitUntil { client.updates.last?.hasTrains ?? false }

        #expect(client.updates.last?.hasTrains == true)
        #expect(clock.now == start)
    }

    @Test func asksNoMoreWhenTheAppLeavesTheScreenAfterTheFirstTrainsCame() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.updates.last?.hasTrains ?? false }
        #expect(provider.callCount == 1)

        model.setAppActive(false)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(provider.callCount == 1)
    }

    @Test func stopsAskingInTheBackgroundOnceTheLiveActivityIsDismissed() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppActive(false)
        let callCount = provider.callCount

        client.isShowing = false
        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { !keeper.isKeeping }

        #expect(provider.callCount == callCount)
        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
    }

    @Test func stopsAskingInTheBackgroundOnceTheQuotaIsExceeded() async {
        provider.answer(.failure(.quotaExceeded), for: Places.stationA)
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { provider.callCount == 1 }
        model.setAppActive(false)

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount == 2 }
        await waitUntil { provider.callCount > 2 }

        #expect(provider.callCount == 2)
    }

    @Test func stopsTheBackgroundLocationWhenDismissedAfterTheQuotaIsExceeded() async {
        provider.answer(.failure(.quotaExceeded), for: Places.stationA)
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { provider.callCount == 1 }
        model.setAppActive(false)
        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount == 2 }

        client.isShowing = false
        await waitUntil { !keeper.isKeeping }

        #expect(keeper.isKeeping == false)
        #expect(model.shownStation == nil)
        #expect(provider.callCount == 2)
    }

    @Test func redrawsTheLiveActivityInTheBackgroundWhenATrainStartsApproachingWithoutAskingPRIM() async {
        let line12 = TransitLine(mode: .metro, name: "12")
        let station = Station(id: "m", name: "Station M", coordinate: Coordinate(48.8600, 2.3600), lines: [line12])
        provider.answer(.success([
            Departure(
                line: line12,
                destination: "Mairie d'Issy",
                time: clock.now.addingTimeInterval(110),
                arrivalTime: clock.now.addingTimeInterval(100)
            )
        ]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { !$0.shownTrains.isEmpty } }
        #expect(client.updates.last?.shownTrains.map(\.status) == [nil])
        model.setAppActive(false)
        let callCount = provider.callCount

        clock.letTimersFire(upTo: 41)
        await waitUntil { client.updates.last?.shownTrains.first?.status == .approaching }

        #expect(client.updates.last?.shownTrains.map(\.status) == [.approaching])
        #expect(provider.callCount == callCount)
    }
}

private extension StationActivityAttributes.ContentState {
    var shownTrains: [LineDirection.Train] {
        trains.linesPage?.lines.flatMap(\.directions).flatMap(\.trains) ?? []
    }

    var hasTrains: Bool {
        trains.linesPage != nil
    }
}
