import Foundation
import Testing
@testable import RATPCore

struct DepartureBoardLineOrderTests {
    private let line1 = TransitLine(mode: .metro, name: "1")
    private let rerA = TransitLine(mode: .rer, name: "A")
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func station(_ name: String, _ lines: TransitLine...) -> Station {
        Station(id: name, name: name, coordinate: Coordinate(48.86, 2.35), lines: lines)
    }

    private func at(minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    @Test func ordersTheLinesOfTheFirstStationFirstThenTheLinesOfEachOtherStationMetroFirstThenRER() {
        let line14 = TransitLine(mode: .metro, name: "14")
        let rerB = TransitLine(mode: .rer, name: "B")
        let board = DepartureBoard(
            departures: [
                Departure(line: rerA, destination: "Boissy", time: at(minutes: 1)),
                Departure(line: line14, destination: "Olympiades", time: at(minutes: 2)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 5)),
                Departure(line: rerB, destination: "Mitry", time: at(minutes: 6))
            ],
            stations: [station("Châtelet - Les Halles", rerB, rerA), station("Châtelet", line14, line1)],
            now: now
        )

        #expect(board.lines == [rerA, rerB, line1, line14])
        #expect(board.groups.map(\.line) == [rerA, rerB, line1, line14])
    }

    @Test func putsTheLinesOfAnotherStationWithTheNameOfTheFirstStationBeforeTheLinesOfACloserStation() {
        let line12 = TransitLine(mode: .metro, name: "12")
        let board = DepartureBoard(
            departures: [],
            stations: [
                Station(id: "metro", name: "Saint-Lazare", coordinate: Coordinate(48.87, 2.32), lines: [line12]),
                station("Havre-Caumartin", line1),
                Station(id: "rer", name: "Saint-Lazare", coordinate: Coordinate(48.87, 2.32), lines: [rerA])
            ],
            now: now
        )

        #expect(board.lines == [line12, rerA, line1])
    }

    @Test(arguments: [
        ("Châtelet - Les Halles", ["A", "B", "D", "4", "1", "7", "11", "14"]),
        ("Opéra", ["3", "7", "8", "A", "9", "E", "12", "13", "14"]),
        ("La Chapelle", ["2", "E", "4", "5", "B", "D"]),
        ("Gare du Nord", ["4", "5", "B", "D", "E", "2"])
    ])
    func ordersTheLinesOfTheBundledHubFromTheHeaderStationToTheFarthestStation(
        stationName: String,
        expected: [String]
    ) throws {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == stationName })
        let hub = catalog.hubStations(of: station)

        let board = DepartureBoard(departures: [], stations: hub, now: now)

        #expect(board.lines.map(\.name) == expected)
        #expect(Set(board.lines) == Set(hub.flatMap(\.lines)))
    }
}
