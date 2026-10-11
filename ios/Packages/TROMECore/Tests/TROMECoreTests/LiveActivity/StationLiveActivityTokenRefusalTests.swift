import Foundation
import Testing
@testable import TROMECore

@MainActor
struct StationLiveActivityTokenRefusalTests {
    private let clock = TestClock()
    private let client = StubStationLiveActivityClient()
    private let line12 = TransitLine(mode: .metro, name: "12")
    private let refused = NextTrainsState.failed(.appTokenRefused)

    private var concorde: Station {
        Station(id: "concorde", name: "Concorde", coordinate: Coordinate(48.8656, 2.3212), lines: [line12])
    }

    private func concordeTrains(inSeconds delays: [TimeInterval]) -> NextTrainsState {
        let departures = delays.map {
            Departure(line: line12, destination: "Mairie d'Issy", time: clock.now.addingTimeInterval($0))
        }
        let board = DepartureBoard(departures: departures, stations: [concorde], now: clock.now)
        return .departures(board, updatedAt: clock.now)
    }

    private func makeModel() -> StationLiveActivityModel {
        StationLiveActivityModel(client: client, now: { [clock] in clock.now })
    }

    @Test func startsWithTheUpdateStateWhenTheServerRefusesTheToken() async {
        let model = makeModel()

        await model.start(station: concorde, trains: refused)

        #expect(client.shownContent?.trains == .noData)
        #expect(client.shownContent?.appNeedsUpdate == true)
        #expect(client.shownContent?.serverIsOut == false)
        #expect(client.shownContent?.dynamicIslandWait(isStale: false).wait == .updateTheApp)
        #expect(model.appNeedsUpdate)
    }

    @Test func keepsTheShownTimesAndSaysToUpdateTheAppOnceTheyAreOld() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let shown = client.shownContent

        await model.update(station: concorde, trains: refused)
        clock.advance(by: 120)
        await model.redraw()

        #expect(client.shownContent?.trains == shown?.trains)
        #expect(client.shownContent?.appNeedsUpdate == true)
        #expect(client.shownContent?.isMarkedStale == true)
        #expect(client.shownContent?.dynamicIslandWait(isStale: true).wait == .updateTheApp)
    }

    @Test func showsTheTimesWithoutTheUpdateStateWhenTheServerAcceptsTheTokenAgain() async {
        let model = makeModel()
        await model.start(station: concorde, trains: refused)

        await model.update(station: concorde, trains: concordeTrains(inSeconds: [120]))

        #expect(client.shownContent?.appNeedsUpdate == false)
        #expect(client.shownContent?.trains.linesPage != nil)
        #expect(!model.appNeedsUpdate)
    }

    @Test func forgetsTheRefusalWhenTheLiveActivityStops() async {
        let model = makeModel()
        await model.start(station: concorde, trains: refused)

        await model.stop()

        #expect(!model.appNeedsUpdate)
    }
}
