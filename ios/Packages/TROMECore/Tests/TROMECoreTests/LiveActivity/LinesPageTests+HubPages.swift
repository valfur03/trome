import Foundation
import Testing
@testable import TROMECore

extension LinesPageTests {
    func pagesWithFakeTrains(at name: String) throws -> [LinesPage] {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == name })
        let hub = catalog.hubStations(of: station)
        let departures = hub.flatMap { station in
            station.lines.flatMap { FakeDeparturesProvider.departures(of: $0, at: station, from: now) }
        }
        let board = DepartureBoard(departures: departures, stations: hub, now: now)
        var pages: [LinesPage] = []
        var index = 0
        repeat {
            let content = StationActivityAttributes.ContentState(
                station: station,
                trains: .departures(board, updatedAt: now),
                now: now,
                firstLineIndex: index
            )
            let page = try #require(content.trains.linesPage)
            pages.append(page)
            index = page.nextFirstIndex
        } while index != 0 && pages.count <= board.lines.count
        return pages
    }

    @Test(arguments: [
        ("Châtelet", ["1", "4", "7", "11", "14", "A", "B", "D"]),
        ("Opéra", ["3", "7", "8", "A", "9", "E", "12", "13", "14"]),
        ("Saint-Lazare", ["3", "12", "13", "14", "E", "9", "A", "7", "8"]),
        ("Gare du Nord", ["4", "5", "B", "D", "E", "2"]),
        ("Châtelet - Les Halles", ["A", "B", "D", "4", "1", "7", "11", "14"]),
        ("Auber", ["A", "3", "9", "7", "8", "E", "12", "13", "14"]),
        ("Gare de Lyon", ["1", "14", "A", "D"])
    ])
    func showsOnePageForEachLineInTheOrderOfTheLinesOfThePlace(station: String, expected: [String]) throws {
        let pages = try pagesWithFakeTrains(at: station)

        #expect(pages.map { $0.lines.map(\.line.name).joined(separator: "+") } == expected)
        #expect(pages.last?.nextFirstIndex == 0)
    }

    @Test func countsTheOtherLinesOfTheStationOnEachPage() throws {
        let pages = try pagesWithFakeTrains(at: "Gare du Nord")

        #expect(pages.map(\.otherLineCount) == [5, 5, 5, 5, 5, 5])
    }

    @Test(arguments: ["Opéra", "Saint-Lazare", "Châtelet", "Nation", "Pigalle", "Maison Blanche", "Gare de l'Est"])
    func drawsTheStripsOnEveryMetroPageOfAStationWithSeveralLines(station: String) throws {
        let pages = try pagesWithFakeTrains(at: station)
        let metroPages = pages.filter { $0.lines.contains { $0.line.mode == .metro } }

        #expect(metroPages.allSatisfy { $0.lines.count == 1 && $0.panamStripsLine == $0.lines.first })
        #expect(pages.filter { $0.lines.contains { $0.line.mode == .rer } }.allSatisfy { $0.panamStripsLine == nil })
    }

    @Test func drawsTheStripsOfALineOfAnotherStationOfTheHubWithTheNameOfThatStation() throws {
        let pages = try pagesWithFakeTrains(at: "Opéra")
        let line13 = try #require(pages.first { $0.lines.first?.line.name == "13" })

        #expect(line13.panamStripsLine?.stationName == "Saint-Lazare")
        #expect(line13.panamStripsLine?.directions.contains { $0.branchEnds != nil } == true)
    }

    @Test func givesEachMetroLineOfTheStationListOnePageOnly() throws {
        let catalog = try StationCatalog.bundled()
        for station in catalog.stations where station.lines.contains(where: { $0.mode == .metro }) {
            let shown = try pagesWithFakeTrains(at: station.name).flatMap(\.lines).map(\.line)
            #expect(shown.count == Set(shown).count, "\(station.name)")
        }
    }
}
