import Foundation
import Testing
@testable import TROMECore

@MainActor
struct StationLiveActivityEndTests {
    private let client = StubStationLiveActivityClient()
    private let abbesses = Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [])
    private let pigalle = Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [])

    private func makeModel() -> StationLiveActivityModel {
        StationLiveActivityModel(client: client, now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private func holdTheEnd(of model: StationLiveActivityModel) async -> Task<Void, Never> {
        client.holdsNextEnd = true
        let stop = Task { await model.stop() }
        for _ in 0..<1_000 where !client.isHoldingAnEnd {
            await Task.yield()
        }
        return stop
    }

    @Test func startsANewLiveActivityWhenAStationComesWhileTheLastOneStillEnds() async {
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)
        let stop = await holdTheEnd(of: model)

        let start = Task { await model.start(station: pigalle, trains: .noLiveData) }
        for _ in 0..<100 {
            await Task.yield()
        }
        client.releaseHeldEnd()
        await stop.value
        await start.value

        #expect(client.started.map(\.stationName) == ["Abbesses", "Pigalle"])
        #expect(client.isShowing)
        #expect(model.isShowing)
        #expect(model.content?.stationName == "Pigalle")
    }

    @Test func sendsNoUpdateToALiveActivityThatEnds() async {
        let model = makeModel()
        await model.start(station: abbesses, trains: .loading)
        let stop = await holdTheEnd(of: model)

        await model.update(station: abbesses, trains: .noLiveData)
        client.releaseHeldEnd()
        await stop.value

        #expect(client.updates.isEmpty)
        #expect(model.isShowing == false)
    }
}
