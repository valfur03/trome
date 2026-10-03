import Foundation
import Testing
@testable import TROMECore

@MainActor
struct CurrentStationModelTests {
    private let abbesses = Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [])
    private let pigalle = Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [])
    private var catalog: StationCatalog {
        StationCatalog(stations: [abbesses, pigalle])
    }

    @Test func hasNoStationBeforeTheFirstPick() {
        let model = CurrentStationModel(catalog: catalog, store: CurrentStationStore(storage: InMemoryKeyValueStore()))

        #expect(model.station == nil)
    }

    @Test func remembersThePickedStation() {
        let storage = InMemoryKeyValueStore()
        CurrentStationModel(catalog: catalog, store: CurrentStationStore(storage: storage)).select(pigalle)

        let model = CurrentStationModel(catalog: catalog, store: CurrentStationStore(storage: storage))

        #expect(model.station == pigalle)
    }

    @Test func switchesToAnotherPickedStation() {
        let model = CurrentStationModel(catalog: catalog, store: CurrentStationStore(storage: InMemoryKeyValueStore()))

        model.select(abbesses)
        model.select(pigalle)

        #expect(model.station == pigalle)
    }

    @Test func forgetsAStationThatIsNoLongerInTheList() {
        let storage = InMemoryKeyValueStore()
        storage.values[CurrentStationStore.key] = Data("removed-station".utf8)

        let model = CurrentStationModel(catalog: catalog, store: CurrentStationStore(storage: storage))

        #expect(model.station == nil)
    }
}
