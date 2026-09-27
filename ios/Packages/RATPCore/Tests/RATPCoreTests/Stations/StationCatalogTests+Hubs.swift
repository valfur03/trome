import Foundation
import Testing
@testable import RATPCore

struct StationCatalogHubsTests {
    private let line4 = TransitLine(mode: .metro, name: "4", stopIds: ["IDFM:4"])
    private let line1 = TransitLine(mode: .metro, name: "1", stopIds: ["IDFM:1"])
    private let rerA = TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:10"])

    private func station(_ id: String, at latitude: Double, _ lines: [TransitLine], hubId: String? = "hub") -> Station {
        Station(id: id, name: id, coordinate: Coordinate(latitude, 2.35), lines: lines, hubId: hubId)
    }

    @Test func givesOnlyTheStationWhenItIsNotPartOfAHub() {
        let alone = station("alone", at: 48.86, [line1], hubId: nil)
        let catalog = StationCatalog(stations: [alone, station("other", at: 48.86, [rerA], hubId: nil)])

        #expect(catalog.hubStations(of: alone) == [alone])
    }

    @Test func addsTheLinesOfTheOtherStationsOfTheHubAfterTheStation() {
        let metro = station("metro", at: 48.8600, [line1])
        let rer = station("rer", at: 48.8610, [rerA])
        let catalog = StationCatalog(stations: [rer, metro, station("elsewhere", at: 48.86, [line4], hubId: "other")])

        #expect(catalog.hubStations(of: metro) == [metro, rer])
        #expect(catalog.hubStations(of: rer) == [rer, metro])
    }

    @Test func takesALineFromTheStationItselfThenFromTheNearestStationOfTheHub() {
        let metro = station("metro", at: 48.8600, [line1, line4])
        let near = station("near", at: 48.8605, [line4, rerA])
        let far = station("far", at: 48.8620, [line4])
        let catalog = StationCatalog(stations: [far, near, metro])

        #expect(catalog.hubStations(of: metro) == [metro, station("near", at: 48.8605, [rerA])])
        #expect(catalog.hubStations(of: far) == [
            far,
            station("near", at: 48.8605, [rerA]),
            station("metro", at: 48.8600, [line1])
        ])
    }

    @Test func showsTheMetroAndRERLinesOfChateletTogether() throws {
        let catalog = try StationCatalog.bundled()
        let chatelet = try #require(catalog.stations.first { $0.name == "Châtelet" })
        let chateletLesHalles = try #require(catalog.stations.first { $0.name == "Châtelet - Les Halles" })

        let lines: (Station) -> [String] = { station in
            catalog.hubStations(of: station).flatMap(\.lines).map(\.displayName).sorted()
        }

        let everyLine = ["Metro 1", "Metro 11", "Metro 14", "Metro 4", "Metro 7", "RER A", "RER B", "RER D"]
        #expect(lines(chatelet) == everyLine)
        #expect(lines(chateletLesHalles) == everyLine)
        #expect(catalog.hubStations(of: chatelet).map(\.name) == ["Châtelet", "Châtelet - Les Halles"])
    }
}
