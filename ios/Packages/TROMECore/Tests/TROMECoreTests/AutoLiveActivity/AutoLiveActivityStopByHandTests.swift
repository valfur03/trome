import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    @Test func startsTheLiveActivityOfAStationThatComesWhileTheStopByHandStillEnds() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        client.holdsNextEnd = true
        let stop = Task { await model.stopByHand() }
        await waitUntil { client.isHoldingAnEnd }

        gps.report(Places.atB)
        await waitUntil { model.shownStation == Places.stationB }
        client.releaseHeldEnd()
        await stop.value
        await waitUntil { client.started.count == 2 }

        #expect(client.started.map(\.stationName) == ["Station A", "Station B"])
        #expect(client.isShowing)
        #expect(keeper.isKeeping)
    }

    @Test func stopsTheBackgroundLocationWhenTheAppOpensWhileTheStopByHandStillEnds() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        client.holdsNextEnd = true
        let stop = Task { await model.stopByHand() }
        await waitUntil { client.isHoldingAnEnd }

        let opening = Task { await activate(model) }
        for _ in 0..<100 {
            await Task.yield()
        }
        client.releaseHeldEnd()
        await stop.value
        await opening.value

        #expect(client.isShowing == false)
        #expect(keeper.isKeeping == false)
    }
}
