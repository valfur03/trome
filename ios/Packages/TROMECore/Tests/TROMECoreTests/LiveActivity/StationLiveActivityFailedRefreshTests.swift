import Foundation
import Testing
@testable import TROMECore

@MainActor
struct StationLiveActivityFailedRefreshTests {
    private let clock = TestClock()
    private let client = StubStationLiveActivityClient()
    private let line12 = TransitLine(mode: .metro, name: "12")
    private let pigalle = Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [])

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

    private func makeModel(store: StationLiveActivityInputsStore? = nil) -> StationLiveActivityModel {
        StationLiveActivityModel(client: client, store: store, now: { [clock] in clock.now })
    }

    private func content(_ station: Station, _ trains: NextTrainsState) -> StationActivityAttributes.ContentState {
        StationActivityAttributes.ContentState(station: station, trains: trains, now: clock.now)
    }

    @Test(arguments: [NextTrainsError.unreachable, .keyRejected, .quotaExceeded, .serviceFailure])
    func keepsTheShownTrainsWhenARefreshFails(error: NextTrainsError) async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let shown = client.shownContent

        await model.update(station: concorde, trains: .failed(error))

        #expect(client.updates.isEmpty)
        #expect(client.shownContent == shown)
        #expect(model.content == shown)
    }

    @Test func keepsDrawingTheKeptTrainsUntilTheFirstShownTrainLeaves() async {
        let model = makeModel()
        let firstTrain = clock.now.addingTimeInterval(120)
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        await model.update(station: concorde, trains: .failed(.unreachable))

        clock.advance(by: 60)
        await model.redraw()

        #expect(client.updates.last?.shownTrainTimes == [firstTrain, firstTrain.addingTimeInterval(280)])
        #expect(client.updates.last?.staleDate == firstTrain)
    }

    @Test func letsTheKeptTrainsGoStaleOnceTheFirstShownTrainHasLeft() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let shown = client.shownContent
        await model.update(station: concorde, trains: .failed(.unreachable))

        clock.advance(by: 120)
        await model.redraw()
        await model.update(station: concorde, trains: .failed(.unreachable))

        #expect(client.updates.isEmpty)
        #expect(client.shownContent == shown)
        #expect(shown?.staleDate == clock.now)
        #expect(model.nextRedrawDate(after: clock.now) == nil)
    }

    @Test func letsTheTrainsSavedByTheLastAppGoStaleOnceTheFirstShownTrainHasLeft() async {
        let store = StationLiveActivityInputsStore(storage: InMemoryKeyValueStore())
        await makeModel(store: store).start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let shown = client.shownContent
        let appStartedAgain = makeModel(store: store)

        clock.advance(by: 120)
        await appStartedAgain.redraw()

        #expect(client.updates.isEmpty)
        #expect(client.shownContent == shown)
    }

    @Test func sendsTheShownContentAgainWhenTheRiderAsksForTheNextLinesOfStaleTimes() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let shown = client.shownContent
        await model.update(station: concorde, trains: .failed(.unreachable))

        clock.advance(by: 120)
        await model.showNextLines()

        #expect(client.updates == [shown])
    }

    @Test func drawsTheTrainsSavedByTheLastAppUntilTheFirstShownTrainLeaves() async {
        let store = StationLiveActivityInputsStore(storage: InMemoryKeyValueStore())
        await makeModel(store: store).start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        let appStartedAgain = makeModel(store: store)

        clock.advance(by: 60)
        await appStartedAgain.redraw()

        let firstTrain = clock.now.addingTimeInterval(60)
        #expect(client.updates.last?.shownTrainTimes == [firstTrain, firstTrain.addingTimeInterval(280)])
    }

    @Test func drawsTheNextTrainWhenTheFirstOneLeavesAfterASuccessfulRefresh() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))

        clock.advance(by: 120)
        await model.redraw()

        #expect(client.updates.last?.shownTrainTimes == [clock.now.addingTimeInterval(280)])
    }

    @Test func showsNoDataWhenTheFirstLoadFails() async {
        let model = makeModel()
        await model.start(station: concorde, trains: .loading)

        await model.update(station: concorde, trains: .failed(.unreachable))

        #expect(client.updates.last?.trains == .noData)
    }

    @Test func showsNoDataWhenARefreshFailsAfterAnAnswerWithNoTrain() async {
        let model = makeModel()
        await model.start(station: concorde, trains: .noLiveData)

        await model.update(station: concorde, trains: .failed(.unreachable))

        #expect(client.updates.last?.trains == .noData)
    }

    @Test func neverShowsTheTrainsOfTheStationLeftBehindWhenTheLoadFailsAfterASwitch() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))

        await model.update(station: pigalle, trains: .loading)
        await model.update(station: pigalle, trains: .failed(.unreachable))

        #expect(client.updates == [content(pigalle, .loading), content(pigalle, .failed(.unreachable))])
        #expect(client.updates.last?.trains == .noData)
    }

    @Test func showsTheNewTrainsAtOnceWhenARefreshWorksAgain() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))
        await model.update(station: concorde, trains: .failed(.unreachable))
        clock.advance(by: 150)

        await model.update(station: concorde, trains: concordeTrains(inSeconds: [60, 300]))
        clock.advance(by: 60)
        await model.redraw()

        #expect(client.updates.count == 2)
        #expect(client.updates.first?.shownTrainTimes == [clock.now, clock.now.addingTimeInterval(240)])
        #expect(client.updates.last?.shownTrainTimes == [clock.now.addingTimeInterval(240)])
    }

    @Test func keepsTheShownTrainsWhenTheLiveActivityStartsAgainAfterAFailedRefresh() async {
        let model = makeModel()
        await model.start(station: concorde, trains: concordeTrains(inSeconds: [120, 400]))

        await model.start(station: concorde, trains: .failed(.unreachable))

        #expect(client.updates.isEmpty)
        #expect(model.isShowing)
    }

    @Test func keepsTheTrainsThatTheLiveActivityShowedBeforeTheAppStartedWhenARefreshFails() async {
        client.isShowing = true
        client.shownContent = content(concorde, concordeTrains(inSeconds: [120, 400]))
        let model = makeModel()

        await model.update(station: concorde, trains: .failed(.unreachable))

        #expect(client.updates.isEmpty)
    }
}

private extension StationActivityAttributes.ContentState {
    var shownTrainTimes: [Date] {
        trains.linesPage?.lines.flatMap(\.directions).flatMap(\.trains).map(\.time) ?? []
    }
}
