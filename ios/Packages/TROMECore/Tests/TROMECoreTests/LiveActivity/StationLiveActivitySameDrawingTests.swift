import Foundation
import Testing
@testable import TROMECore

/// iOS draws each update of the Live Activity again in the widget process, and an update that comes during a draw
/// cancels it: an update that draws the same must not reach iOS.
@MainActor
struct StationLiveActivitySameDrawingTests {
    private let clock = TestClock()
    private let client = StubStationLiveActivityClient()
    private let line2 = TransitLine(mode: .metro, name: "2")
    private let pigalle = Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [])
    private let anvers = Station(id: "anvers", name: "Anvers", coordinate: Coordinate(48.8829, 2.3442), lines: [])

    private var barbes: Station {
        Station(id: "barbes", name: "Barbès - Rochechouart", coordinate: Coordinate(48.8838, 2.3506), lines: [line2])
    }

    private var barbesTrains: NextTrainsState {
        let departure = Departure(line: line2, destination: "Nation", time: clock.now.addingTimeInterval(300))
        let board = DepartureBoard(departures: [departure], stations: [barbes], now: clock.now)
        return .departures(board, updatedAt: clock.now)
    }

    private func makeModel() -> StationLiveActivityModel {
        StationLiveActivityModel(client: client, now: { [clock] in clock.now })
    }

    @Test func sendsNoUpdateOfTheSameStationWithNoTimesALittleLater() async {
        let model = makeModel()
        await model.start(station: pigalle, trains: .missingKey)

        clock.advance(by: 1)
        await model.update(station: pigalle, trains: .missingKey)

        #expect(client.started.map(\.stationName) == ["Pigalle"])
        #expect(client.updates.isEmpty)
        #expect(model.content?.updatedAt == clock.now)
    }

    /// If iOS failed to draw the last update, the Live Activity still shows the station before it: the next
    /// refresh sends it again.
    @Test func sendsTheSameStationWithNoTimesAgainOnceIOSHadTheTimeToDrawIt() async {
        let model = makeModel()
        await model.start(station: pigalle, trains: .missingKey)
        await model.update(station: anvers, trains: .missingKey)

        clock.advance(by: StationLiveActivityModel.sameDrawingWait)
        await model.update(station: anvers, trains: .missingKey)

        #expect(client.updates.map(\.stationName) == ["Anvers", "Anvers"])
    }

    @Test func sendsOneUpdateForASwitchToAStationWithNoTimes() async {
        let model = makeModel()
        await model.start(station: pigalle, trains: .missingKey)

        clock.advance(by: 4)
        await model.update(station: anvers, trains: .missingKey)
        clock.advance(by: 1)
        await model.update(station: anvers, trains: .failed(.unreachable))

        #expect(client.updates.map(\.stationName) == ["Anvers"])
        #expect(client.shownContent?.stationName == "Anvers")
    }

    @Test func sendsTheSameTrainsAgainLaterBecauseTheMinutesCountFromTheTimeOfTheContent() async {
        let model = makeModel()
        await model.start(station: barbes, trains: barbesTrains)
        let trains = barbesTrains

        clock.advance(by: 60)
        await model.update(station: barbes, trains: trains)

        #expect(client.updates.count == 1)
        #expect(client.updates.first?.updatedAt == clock.now)
    }

    @Test func sendsWhatTheServerSaysEvenWithNoTimes() async {
        let model = makeModel()
        await model.start(station: pigalle, trains: .missingKey)

        clock.advance(by: 1)
        await model.update(station: pigalle, trains: .failed(.serverOut(retryAt: clock.now.addingTimeInterval(60))))

        #expect(client.updates.map(\.serverIsOut) == [true])
    }

    @Test func sendsTheFirstUpdateOfANewLiveActivityAfterTheLastOneEnded() async {
        let model = makeModel()
        await model.start(station: anvers, trains: .missingKey)
        await model.stop()
        client.isShowing = true
        client.shownContent = StationActivityAttributes.ContentState(
            station: pigalle,
            trains: .missingKey,
            now: clock.now
        )

        clock.advance(by: 1)
        await model.start(station: anvers, trains: .missingKey)

        #expect(client.updates.map(\.stationName) == ["Anvers"])
    }
}
