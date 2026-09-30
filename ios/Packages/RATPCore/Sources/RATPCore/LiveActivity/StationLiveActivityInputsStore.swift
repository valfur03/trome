import Foundation

struct StationLiveActivityInputs: Equatable {
    let station: Station
    let trains: NextTrainsState
}

public struct StationLiveActivityInputsStore {
    public static let key = "stationLiveActivity.inputs"

    private struct Saved: Codable {
        let station: Station
        let trains: SavedTrains
    }

    private enum SavedTrains: Codable {
        case departures(stations: [Station], departures: [Departure], updatedAt: Date)
        case noLiveData
    }

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    func load() -> StationLiveActivityInputs? {
        guard let data = storage.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return nil
        }
        switch saved.trains {
        case .departures(let stations, let departures, let updatedAt):
            let board = DepartureBoard(departures: departures, stations: stations, now: updatedAt)
            return StationLiveActivityInputs(station: saved.station, trains: .departures(board, updatedAt: updatedAt))
        case .noLiveData:
            return StationLiveActivityInputs(station: saved.station, trains: .noLiveData)
        }
    }

    func save(_ inputs: StationLiveActivityInputs?) {
        let saved = inputs.flatMap { inputs in
            Self.savedTrains(inputs.trains).map { Saved(station: inputs.station, trains: $0) }
        }
        storage.set(saved.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key)
    }

    private static func savedTrains(_ trains: NextTrainsState) -> SavedTrains? {
        switch trains {
        case .departures(let board, let updatedAt):
            .departures(
                stations: board.stations,
                departures: board.departures + board.laterDepartures,
                updatedAt: updatedAt
            )
        case .noLiveData:
            .noLiveData
        case .idle, .missingKey, .loading, .failed:
            nil
        }
    }
}
