import Foundation
import Testing
@testable import TROMECore

final class InMemoryKeyValueStore: KeyValueStore {
    var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}

struct LocationSourceStoreTests {
    private let chatelet = FakePosition(name: "Châtelet", coordinate: Coordinate(48.85855, 2.34743))

    @Test func usesTheRealGPSWhenNothingIsSaved() {
        let store = LocationSourceStore(storage: InMemoryKeyValueStore())

        #expect(store.load() == .realGPS)
    }

    @Test func loadsTheSavedFakePosition() {
        let storage = InMemoryKeyValueStore()
        LocationSourceStore(storage: storage).save(.fake(chatelet))

        #expect(LocationSourceStore(storage: storage).load() == .fake(chatelet))
    }

    @Test func loadsTheRealGPSAfterSwitchingBack() {
        let store = LocationSourceStore(storage: InMemoryKeyValueStore())
        store.save(.fake(chatelet))
        store.save(.realGPS)

        #expect(store.load() == .realGPS)
    }

    @Test func usesTheRealGPSWhenTheSavedValueIsUnreadable() {
        let storage = InMemoryKeyValueStore()
        storage.values[LocationSourceStore.key] = Data("not json".utf8)

        #expect(LocationSourceStore(storage: storage).load() == .realGPS)
    }

    @Test func goesBackToTheRealGPSWhenTheLaunchAsksForAReset() {
        let store = LocationSourceStore(storage: InMemoryKeyValueStore())
        store.save(.fake(chatelet))

        store.resetIfAsked(by: ["TROME", LocationSourceStore.resetArgument])

        #expect(store.load() == .realGPS)
    }

    @Test func keepsTheFakePositionWhenTheLaunchAsksForNoReset() {
        let store = LocationSourceStore(storage: InMemoryKeyValueStore())
        store.save(.fake(chatelet))

        store.resetIfAsked(by: ["TROME"])

        #expect(store.load() == .fake(chatelet))
    }
}
