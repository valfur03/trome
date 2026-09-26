import Foundation
import Observation

public struct CurrentStationStore {
    public static let key = "currentStation.id"

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    public func load(from catalog: StationCatalog) -> Station? {
        guard let data = storage.data(forKey: Self.key), let id = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        return catalog.station(withId: id)
    }

    public func save(_ station: Station) {
        storage.set(Data(station.id.utf8), forKey: Self.key)
    }
}

@MainActor
@Observable
public final class CurrentStationModel {
    public private(set) var station: Station?

    private let store: CurrentStationStore

    public init(catalog: StationCatalog, store: CurrentStationStore) {
        self.store = store
        self.station = store.load(from: catalog)
    }

    public func select(_ station: Station) {
        self.station = station
        store.save(station)
    }
}
