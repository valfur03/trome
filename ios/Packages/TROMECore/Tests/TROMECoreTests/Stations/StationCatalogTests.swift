import Foundation
import Testing
@testable import TROMECore

struct StationCatalogTests {
    private let near = Station(
        id: "near",
        name: "Near",
        coordinate: Coordinate(48.8600, 2.3500),
        lines: [TransitLine(mode: .metro, name: "1")]
    )
    private let far = Station(
        id: "far",
        name: "Far",
        coordinate: Coordinate(48.8700, 2.3500),
        lines: [TransitLine(mode: .rer, name: "A")]
    )

    @Test func findsTheClosestStation() {
        let catalog = StationCatalog(stations: [far, near])

        let nearby = catalog.nearestStation(to: Coordinate(48.8610, 2.3500))

        #expect(nearby?.station == near)
        #expect(abs((nearby?.distanceMeters ?? 0) - 111) < 1)
    }

    @Test func findsNoStationBeyondWalkingDistance() {
        let catalog = StationCatalog(stations: [near, far])

        #expect(catalog.nearestStation(to: Coordinate(48.9000, 2.3500)) == nil)
    }

    @Test func decodesStationsFromJSON() throws {
        let json = """
        {"date": "2026-09-27", "stations": [
          {"id": "IDFM:1", "name": "Nation", "latitude": 48.848, "longitude": 2.396,
           "lines": [{"mode": "metro", "name": "1", "stopIds": ["IDFM:22080"]},
                     {"mode": "rer", "name": "A", "stopIds": ["IDFM:473875"]}]}]}
        """

        let catalog = try StationCatalog(jsonData: Data(json.utf8))

        #expect(catalog.stations.first?.name == "Nation")
        #expect(catalog.stations.first?.lines.map(\.displayName) == ["Metro 1", "RER A"])
    }

    @Test func rejectsModesOtherThanMetroAndRER() {
        let json = """
        {"date": "2026-09-27", "stations": [
          {"id": "IDFM:2", "name": "Jean Rostand", "latitude": 48.9, "longitude": 2.45,
           "lines": [{"mode": "tram", "name": "T1", "stopIds": []}]}]}
        """

        #expect(throws: DecodingError.self) { try StationCatalog(jsonData: Data(json.utf8)) }
    }

    @Test func listsEveryStationInAlphabeticalOrderWhenTheSearchIsEmpty() {
        let catalog = StationCatalog(stations: [
            station("Étienne Marcel"), station("Nation"), station("Alésia"), station("Alma - Marceau")
        ])

        let names = catalog.stations(matching: " ").map(\.name)

        #expect(names == ["Alésia", "Alma - Marceau", "Étienne Marcel", "Nation"])
    }

    @Test(arguments: [
        ("chatelet", ["Châtelet", "Châtelet - Les Halles"]),
        ("LA DEFENSE", ["La Défense"]),
        ("saint lazare", ["Haussmann Saint-Lazare", "Saint-Lazare"]),
        ("chatelet-les", ["Châtelet - Les Halles"]),
        ("madeleine", [])
    ])
    func findsStationsByPartOfTheirName(query: String, expectedNames: [String]) {
        let catalog = StationCatalog(stations: [
            station("Saint-Lazare"), station("Châtelet - Les Halles"), station("La Défense"),
            station("Châtelet"), station("Haussmann Saint-Lazare")
        ])

        #expect(catalog.stations(matching: query).map(\.name) == expectedNames)
    }

    private func station(_ name: String) -> Station {
        Station(
            id: name,
            name: name,
            coordinate: Coordinate(48.86, 2.35),
            lines: [TransitLine(mode: .metro, name: "1")]
        )
    }
}

struct BundledStationCatalogTests {
    private let catalog: StationCatalog

    init() throws {
        catalog = try StationCatalog.bundled()
    }

    @Test func coversEveryMetroAndRERLine() {
        let lines = Set(catalog.stations.flatMap(\.lines).map(\.displayName))
        let metroLines = (1...14).map { "Metro \($0)" } + ["Metro 3bis", "Metro 7bis"]
        let rerLines = ["A", "B", "C", "D", "E"].map { "RER \($0)" }

        #expect(lines == Set(metroLines + rerLines))
    }

    @Test(arguments: [
        (48.8585, 2.3474, "Châtelet"),
        (48.8584, 2.2945, "Champ de Mars Tour Eiffel"),
        (48.8807, 2.3553, "Gare du Nord"),
        (48.8920, 2.2380, "La Défense"),
        (48.8702, 2.7830, "Marne-la-Vallée - Chessy"),
        (48.7030, 2.0710, "Saint-Rémy-lès-Chevreuse")
    ])
    func findsTheNearestStation(latitude: Double, longitude: Double, expectedName: String) {
        let nearby = catalog.nearestStation(to: Coordinate(latitude, longitude))

        #expect(nearby?.station.name == expectedName)
    }

    @Test(arguments: [
        ("Châtelet", ["Metro 1", "Metro 4", "Metro 7", "Metro 11", "Metro 14"]),
        ("Gare du Nord", ["Metro 4", "Metro 5", "RER B", "RER D"]),
        ("Nation", ["Metro 1", "Metro 2", "Metro 6", "Metro 9", "RER A"]),
        ("La Défense", ["Metro 1", "RER A", "RER E"]),
        ("Rosny-Bois-Perrier", ["Metro 11", "RER E"]),
        ("Aéroport Charles de Gaulle 1", ["RER B"])
    ])
    func namesStationsLikeInTheRealWorld(name: String, expectedLines: [String]) {
        let matches = catalog.stations.filter { $0.name == name }

        #expect(matches.map { $0.lines.map(\.displayName) } == [expectedLines])
    }

    @Test func hasNoBrokenEntry() {
        for station in catalog.stations {
            #expect(!station.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(station.id) has no name")
            #expect(station.name == station.name.trimmingCharacters(in: .whitespaces), "\(station.name)")
            #expect(!station.lines.isEmpty, "\(station.name) has no line")
            let lineNames = station.lines.map(\.displayName)
            #expect(Set(lineNames).count == lineNames.count, "\(station.name) lists a line twice")
        }
        #expect(Set(catalog.stations.map(\.id)).count == catalog.stations.count)
    }

    @Test func listsEachStationOnlyOnce() {
        let stationsByName = Dictionary(grouping: catalog.stations) { $0.name.comparisonKey }
        for stations in stationsByName.values {
            for (index, station) in stations.enumerated() {
                for other in stations[(index + 1)...] {
                    #expect(
                        station.coordinate.distance(to: other.coordinate) > StationCatalog.walkingDistanceMeters,
                        "\(station.name) and \(other.name) look like the same station"
                    )
                }
            }
        }
    }

    @Test func listsMoreThanFiveHundredStations() {
        #expect(catalog.stations.count > 500)
    }

    @Test func findsBothChateletStationsWithTheirLines() {
        let matches = catalog.stations(matching: "chatelet")

        #expect(matches.map(\.name) == ["Châtelet", "Châtelet - Les Halles"])
        #expect(matches.map { $0.lines.first?.displayName } == ["Metro 1", "RER A"])
    }

    @Test func findsNoStationFarFromAnyStation() {
        #expect(catalog.nearestStation(to: TestPlaces.farFromAnyStation.coordinate) == nil)
    }

    @Test func ignoresACloserTramStop() {
        let jeanRostandTramStop = Coordinate(48.9078, 2.4544)

        let nearby = catalog.nearestStation(to: jeanRostandTramStop)

        #expect(nearby?.station.name != "Jean Rostand")
    }
}

private extension String {
    var comparisonKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
