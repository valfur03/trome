import Foundation
import Testing
@testable import TROMECore

@MainActor
struct StationLiveActivityRedrawTests {
    private let clock = TestClock()
    private let client = StubStationLiveActivityClient()
    private let line12 = TransitLine(mode: .metro, name: "12")

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

    @Test func plansTheRedrawWhenTheSoonestTrainLeaves() async {
        let model = makeModel()
        let soonestTrain = clock.now.addingTimeInterval(5)
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [5, 240]))

        clock.advance(by: 2)

        #expect(model.nextRedrawDate(after: clock.now) == soonestTrain)
    }

    @Test func plansTheRedrawAtOnceWhenTheSoonestTrainLeftSinceTheLastDraw() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [5, 240]))

        clock.advance(by: 8)

        #expect(model.nextRedrawDate(after: clock.now) == clock.now)
    }

    @Test func redrawsWithoutTheTrainThatLeftAndPlansTheNextRedrawLater() async {
        let model = makeModel()
        let laterTrain = clock.now.addingTimeInterval(240)
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [5, 240]))
        clock.advance(by: 8)

        await model.redraw()

        #expect(client.updates.last?.shownTrainTimes == [laterTrain])
        #expect(client.updates.last?.staleDate == laterTrain)
        #expect(model.nextRedrawDate(after: clock.now).map { $0 > clock.now } == true)
    }
}

private extension StationActivityAttributes.ContentState {
    var shownTrainTimes: [Date] {
        trains.linesPage?.lines.flatMap(\.directions).flatMap(\.trains).map(\.time) ?? []
    }
}
