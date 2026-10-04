import Foundation
import Testing
@testable import TROMECore

@MainActor
struct StationLiveActivityServerOutTests {
    private let clock = TestClock()
    private let client = StubStationLiveActivityClient()
    private let line12 = TransitLine(mode: .metro, name: "12")

    private var concorde: Station {
        Station(id: "concorde", name: "Concorde", coordinate: Coordinate(48.8656, 2.3212), lines: [line12])
    }

    private var serverOut: NextTrainsState {
        .failed(.serverOut(retryAt: clock.now.addingTimeInterval(1_840)))
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

    @Test func keepsTheShownTimesAndSaysTheServerIsOutWhenTheServerIsOut() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let shown = client.shownContent

        await model.update(station: concorde, trains: serverOut)

        var expected = shown
        expected?.serverIsOut = true
        #expect(client.updates == [expected].compactMap { $0 })
        #expect(client.shownContent?.trains == shown?.trains)
        #expect(client.shownContent?.staleDate == shown?.staleDate)
        #expect(model.serverRetryAt == clock.now.addingTimeInterval(1_840))
    }

    @Test func sendsNothingMoreWhileTheServerStaysOut() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        await model.update(station: concorde, trains: serverOut)

        clock.advance(by: 30)
        await model.update(station: concorde, trains: serverOut)

        #expect(client.updates.count == 1)
    }

    @Test func keepsSayingTheServerIsOutWhileItDrawsTheKeptTimes() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        await model.update(station: concorde, trains: serverOut)

        clock.advance(by: 60)
        await model.redraw()

        #expect(client.updates.count == 2)
        #expect(client.updates.last?.serverIsOut == true)
        #expect(client.updates.last?.trains.linesPage != nil)
    }

    @Test func saysTheServerIsOutWhenTheLiveActivityStartsWhileTheServerIsOut() async {
        let model = makeModel()

        await model.start(station: concorde, trains: .loading)
        await model.update(station: concorde, trains: serverOut)

        #expect(client.started.last?.serverIsOut == false)
        #expect(client.updates.last?.trains == .noData)
        #expect(client.updates.last?.serverIsOut == true)
    }

    @Test func startsWithTheServerOutWordsWhenTheFirstAnswerIsOut() async {
        let model = makeModel()

        await model.start(station: concorde, trains: serverOut)

        #expect(client.started.last?.trains == .noData)
        #expect(client.started.last?.serverIsOut == true)
    }

    @Test func showsTheNewTimesWithoutTheServerOutWordsWhenTheyComeBack() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        await model.update(station: concorde, trains: serverOut)

        clock.advance(by: 1_840)
        await model.update(station: concorde, trains: concordeTrains(inSeconds: [60, 300]))

        #expect(client.updates.last?.serverIsOut == false)
        #expect(client.updates.last?.trains.linesPage != nil)
        #expect(model.serverRetryAt == nil)
    }

    @Test(arguments: [NextTrainsError.unreachable, .serviceFailure])
    func givesBackTheUsualWordsWhenAnotherProblemFollows(error: NextTrainsError) async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        await model.update(station: concorde, trains: serverOut)

        await model.update(station: concorde, trains: .failed(error))

        #expect(client.updates.last?.serverIsOut == false)
        #expect(model.serverRetryAt == nil)
    }

    @Test func forgetsTheRetryTimeWhenTheLiveActivityStops() async {
        let model = makeModel()
        await model.start(station: concorde, trains: serverOut)

        await model.stop()

        #expect(model.serverRetryAt == nil)
    }
}
