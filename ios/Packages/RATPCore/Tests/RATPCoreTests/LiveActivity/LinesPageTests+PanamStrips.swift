import Foundation
import Testing
@testable import RATPCore

extension LinesPageTests {
    private func page(at name: String, trains: (Station, [Station]) -> NextTrainsState) throws -> LinesPage {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == name })
        let hub = catalog.hubStations(of: station)
        let content = StationActivityAttributes.ContentState(station: station, trains: trains(station, hub), now: now)
        return try #require(content.trains.linesPage)
    }

    private func pageWithFakeTrains(at name: String) throws -> LinesPage {
        try page(at: name) { _, hub in
            let departures = hub.flatMap { station in
                station.lines.flatMap { FakeDeparturesProvider.departures(of: $0, at: station, from: now) }
            }
            return .departures(DepartureBoard(departures: departures, stations: hub, now: now), updatedAt: now)
        }
    }

    @Test(arguments: ["Lamarck - Caulaincourt", "Brochant", "Villejuif - Louis Aragon", "Porte d'Italie"])
    func drawsTheStripsForOneMetroLineWithOneEndInEachDirection(station: String) throws {
        let page = try pageWithFakeTrains(at: station)

        #expect(page.panamStripsLine == page.lines.first)
    }

    @Test(arguments: ["La Fourche", "Maison Blanche", "Châtillon - Montrouge", "La Courneuve - 8 Mai 1945"])
    func keepsTheRowsWhereADirectionOfTheLineHasTwoEnds(station: String) throws {
        #expect(try pageWithFakeTrains(at: station).panamStripsLine == nil)
    }

    @Test(arguments: ["Place d'Italie", "Châtelet", "Sartrouville", "Cité Universitaire"])
    func keepsTheRowsForAHubOrAnRERLine(station: String) throws {
        #expect(try pageWithFakeTrains(at: station).panamStripsLine == nil)
    }

    @Test func drawsTheStripsWhenPRIMHasNoTrainForTheStation() throws {
        let page = try page(at: "Lamarck - Caulaincourt") { _, _ in .noLiveData }

        #expect(page.panamStripsLine?.directions == [])
    }

    @Test func keepsTheRowsWhileTheTrainsOfADirectionGoToTwoPlaces() {
        let line6 = TransitLine(mode: .metro, name: "6")
        let direction = LineDirection(
            label: "Charles de Gaulle - Étoile",
            trains: [
                .init(time: now.addingTimeInterval(120), destination: "Trocadéro"),
                .init(time: now.addingTimeInterval(360), destination: "Charles de Gaulle - Étoile")
            ]
        )
        let page = LinesPage(
            lines: [LineTrains(line: line6, directions: [direction])],
            allLines: [line6],
            firstIndex: 0,
            soonestTrain: nil
        )

        #expect(page.panamStripsLine == nil)
    }

    @Test func keepsTheRowsOfAContentThatAnOlderAppWrote() throws {
        let line = LineTrains(line: TransitLine(mode: .metro, name: "12"), directions: [])
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any]
        )
        json.removeValue(forKey: "hasADirectionWithTwoEnds")
        let older = try JSONDecoder().decode(LineTrains.self, from: JSONSerialization.data(withJSONObject: json))
        let page = LinesPage(lines: [older], allLines: [older.line], firstIndex: 0, soonestTrain: nil)

        #expect(page.panamStripsLine == nil)
    }
}
