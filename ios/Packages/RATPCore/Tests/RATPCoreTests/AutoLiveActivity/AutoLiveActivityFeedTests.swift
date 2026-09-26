import Foundation
import Testing
@testable import RATPCore

extension AutoLiveActivityModelTests {
    @Test func feedsTheLiveActivityAgainWhenRelaunchedWhileItShows() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { !client.updates.isEmpty }
        let callCount = provider.callCount

        let relaunched = makeModel()
        await waitUntil { provider.callCount > callCount }

        #expect(provider.callCount > callCount)
        withExtendedLifetime((model, relaunched)) {}
    }

    @Test func feedsTheLiveActivityWithTheTrainsOfItsOwnStation() async {
        provider.answer(.failure(.unreachable), for: Places.stationA)
        let model = makeModel()

        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.updates.contains { $0.trains == .noData } }

        #expect(client.updates.last?.stationName == "Station A")
        #expect(client.updates.last?.trains == .noData)
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
        await model.setAppActive(false)
        let callCount = provider.callCount

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount >= callCount + 2 }

        #expect(provider.callCount >= callCount + 2)
        #expect(client.isShowing)
    }

    @Test func stopsAskingInTheBackgroundOnceTheLiveActivityIsDismissed() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await model.setAppActive(false)
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
        await model.setAppActive(false)

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
        await model.setAppActive(false)
        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { provider.callCount == 2 }

        client.isShowing = false
        await waitUntil { !keeper.isKeeping }

        #expect(keeper.isKeeping == false)
        #expect(model.shownStation == nil)
        #expect(provider.callCount == 2)
    }
}
