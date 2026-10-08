import Foundation
import Testing
@testable import TROMECore

struct StationLiveActivityInputsStoreTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line1 = TransitLine(mode: .metro, name: "1", stopIds: ["IDFM:1"])
    private let lineA = TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:2"])

    private var chatelet: Station {
        Station(id: "chatelet", name: "Châtelet", coordinate: Coordinate(48.8586, 2.3474), lines: [line1])
    }

    private var lesHalles: Station {
        Station(
            id: "les-halles",
            name: "Châtelet - Les Halles",
            coordinate: Coordinate(48.8617, 2.3470),
            lines: [lineA]
        )
    }

    private var hubTrains: NextTrainsState {
        let departures = [
            Departure(line: line1, destination: "La Défense", time: now.addingTimeInterval(90), arrivalTime: now),
            Departure(line: lineA, destination: "Marne-la-Vallée", time: now.addingTimeInterval(240), isAtStop: true),
            Departure(line: line1, destination: "Château de Vincennes", time: now.addingTimeInterval(4_000))
        ]
        let board = DepartureBoard(departures: departures, stations: [chatelet, lesHalles], now: now)
        return .departures(board, updatedAt: now)
    }

    @Test func loadsTheSavedTrainsOfAHub() {
        let storage = InMemoryKeyValueStore()
        let inputs = StationLiveActivityInputs(station: chatelet, trains: hubTrains)

        StationLiveActivityInputsStore(storage: storage).save(inputs)

        #expect(StationLiveActivityInputsStore(storage: storage).load() == inputs)
    }

    @Test func loadsAStationWithNoLiveData() {
        let storage = InMemoryKeyValueStore()
        let inputs = StationLiveActivityInputs(station: chatelet, trains: .noLiveData)

        StationLiveActivityInputsStore(storage: storage).save(inputs)

        #expect(StationLiveActivityInputsStore(storage: storage).load() == inputs)
    }

    @Test func loadsNothingWhenNothingIsSaved() {
        #expect(StationLiveActivityInputsStore(storage: InMemoryKeyValueStore()).load() == nil)
    }

    @Test(arguments: [NextTrainsState.idle, .missingKey, .loading, .failed(.unreachable)])
    func forgetsTheSavedTrainsForTrainsThatCannotBeShownAgain(trains: NextTrainsState) {
        let store = StationLiveActivityInputsStore(storage: InMemoryKeyValueStore())
        store.save(StationLiveActivityInputs(station: chatelet, trains: hubTrains))

        store.save(StationLiveActivityInputs(station: chatelet, trains: trains))

        #expect(store.load() == nil)
    }
}

extension StationLiveActivityInputsStoreTests {
    @Test func loadsTheStopsThatDidNotAnswerAndTheTimesKeptForThem() {
        let storage = InMemoryKeyValueStore()
        let kept = Departure(line: line1, destination: "La Défense", time: now.addingTimeInterval(120))
        let board = DepartureBoard(
            departures: [Departure(line: lineA, destination: "Marne-la-Vallée", time: now.addingTimeInterval(240))],
            stations: [chatelet, lesHalles],
            now: now,
            unansweredStops: ["STIF:StopPoint:Q:1:"],
            earlierDepartures: [kept]
        )
        let inputs = StationLiveActivityInputs(station: chatelet, trains: .departures(board, updatedAt: now))

        StationLiveActivityInputsStore(storage: storage).save(inputs)

        #expect(StationLiveActivityInputsStore(storage: storage).load() == inputs)
    }
}
