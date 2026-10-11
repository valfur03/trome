import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    private func arriveRefused(in model: AutoLiveActivityModel) async {
        provider.answer(.failure(.appTokenRefused), for: Places.stationA)
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.shownContent?.appNeedsUpdate == true }
    }

    @Test func makesNoCallInTheBackgroundAfterARefusalOfTheToken() async {
        let model = makeModel()
        await arriveRefused(in: model)
        let callCount = provider.callCount

        model.setAppPhase(.background)
        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        try? await Task.sleep(for: .milliseconds(200))

        #expect(callCount == 1)
        #expect(provider.callCount == callCount)
        #expect(client.shownContent?.appNeedsUpdate == true)
        #expect(client.shownContent?.trains == .noData)
    }

    @Test func asksAgainWhenTheRiderOpensTheAppAfterARefusalOfTheToken() async {
        let model = makeModel()
        await arriveRefused(in: model)
        model.setAppPhase(.background)
        provider.answer(.success([]), for: Places.stationA)

        await activate(model)
        await waitUntil { client.shownContent?.appNeedsUpdate == false }

        #expect(provider.callCount == 2)
        #expect(client.shownContent?.appNeedsUpdate == false)
        #expect(client.shownContent?.trains != .noData)
    }

    @Test func asksAgainWhenANewLiveActivityStartsAfterARefusalOfTheToken() async {
        let model = makeModel()
        await arriveRefused(in: model)
        await model.stopByHand()

        await model.startByHand(Places.stationA)
        await waitUntil { provider.callCount == 2 }

        #expect(provider.callCount == 2)
        #expect(client.shownContent?.appNeedsUpdate == true)
    }
}
