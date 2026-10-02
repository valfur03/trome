import Foundation
import Testing
@testable import RATPCore

extension LineDirectionsTests {
    private struct ShownTrain: Equatable {
        let destination: String
        let minutes: Int
    }

    private struct ShownDirection: Equatable {
        let label: String
        let trains: [ShownTrain]
    }

    private var rerA: TransitLine {
        TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:43224"])
    }

    private func rerQuay(_ code: Int) -> String {
        "STIF:StopPoint:Q:\(code):"
    }

    private func liveActivityRows(
        of fixture: String,
        at stationName: String,
        now: Date
    ) throws -> [ShownDirection] {
        let catalogStation = try #require(try StationCatalog.bundled().stations.first { $0.name == stationName })
        let station = Station(
            id: catalogStation.id,
            name: catalogStation.name,
            coordinate: catalogStation.coordinate,
            lines: catalogStation.lines.filter { $0.mode == .rer && $0.name == "A" }
        )
        let visits = try StopMonitoringResponse.visits(from: Fixture.data(fixture))
        let departures = PRIMDeparturesProvider.departures(from: visits, at: [station])
        let board = DepartureBoard(departures: departures, stations: [station], now: now)
        let content = StationActivityAttributes.ContentState(
            station: station,
            trains: .departures(board, updatedAt: now),
            now: now
        )
        let lines = try #require(content.trains.linesPage?.lines)
        return lines.flatMap(\.directions).map { direction in
            ShownDirection(label: direction.label, trains: direction.trains.map { train in
                ShownTrain(destination: train.destination, minutes: train.countdownMinutes(at: now))
            })
        }
    }

    private var west: String { "Saint-Germain-en-Laye / Cergy le Haut / Poissy" }
    private var east: String { "Boissy-Saint-Léger / Marne-la-Vallée - Chessy" }

    @Test func keepsTheNextSaintGermainTrainAtVincennesWhenATrainGoesToSartrouville() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-vincennes-rer-a-2139",
            at: "Vincennes",
            now: Fixture.date("2026-10-01T19:39:00Z")
        )

        #expect(rows == [
            ShownDirection(label: west, trains: [
                ShownTrain(destination: "Poissy", minutes: 2),
                ShownTrain(destination: "Saint-Germain-en-Laye", minutes: 6)
            ]),
            ShownDirection(label: east, trains: [
                ShownTrain(destination: "Boissy-Saint-Léger", minutes: 4),
                ShownTrain(destination: "Marne-la-Vallée - Chessy", minutes: 12)
            ])
        ])
    }

    @Test func showsTheSartrouvilleTrainAmongTheWestTrainsAtVincennes() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-vincennes-rer-a-2143",
            at: "Vincennes",
            now: Fixture.date("2026-10-01T19:43:00Z")
        )

        #expect(rows == [
            ShownDirection(label: west, trains: [
                ShownTrain(destination: "Saint-Germain-en-Laye", minutes: 2),
                ShownTrain(destination: "Sartrouville", minutes: 9)
            ]),
            ShownDirection(label: east, trains: [
                ShownTrain(destination: "Marne-la-Vallée - Chessy", minutes: 8),
                ShownTrain(destination: "Boissy-Saint-Léger", minutes: 12)
            ])
        ])
    }

    @Test func keepsTheNextSaintGermainTrainAtChateletWhenTrainsHaveNoQuay() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-chatelet-rer-a-2148",
            at: "Châtelet - Les Halles",
            now: Fixture.date("2026-10-01T19:48:00Z")
        )

        #expect(rows == [
            ShownDirection(label: west, trains: [
                ShownTrain(destination: "Poissy", minutes: 1),
                ShownTrain(destination: "Saint-Germain-en-Laye", minutes: 7)
            ]),
            ShownDirection(label: east, trains: [ShownTrain(destination: "Marne-la-Vallée - Chessy", minutes: 9)])
        ])
    }

    @Test func putsAShortTripToAStationOfTheBranchesOfOneSideInThatSideAtAnRERTrunkStation() {
        let result = directions(of: rerA, at: "Vincennes", [
            train(rerA, to: "Saint-Germain-en-Laye", inMinutes: 2, from: rerQuay(1)),
            train(rerA, to: "Rueil-Malmaison", inMinutes: 4, from: rerQuay(3)),
            train(rerA, to: "Boissy-Saint-Léger", inMinutes: 5, from: rerQuay(2)),
            train(rerA, to: "Torcy", inMinutes: 7, from: rerQuay(4))
        ])

        #expect(result.map(\.label) == [west, east])
        #expect(result.map { $0.trains.map(\.destination) } == [
            ["Saint-Germain-en-Laye", "Rueil-Malmaison"],
            ["Boissy-Saint-Léger", "Torcy"]
        ])
    }

    @Test func neverMakesAThirdDirectionForATrainOfUnknownSideAtAnRERTrunkStation() {
        let result = directions(of: rerA, at: "Vincennes", [
            train(rerA, to: "Nanterre Préfecture", inMinutes: 1, from: rerQuay(3)),
            train(rerA, to: "Saint-Germain-en-Laye", inMinutes: 2, from: rerQuay(1)),
            train(rerA, to: "Poissy", inMinutes: 6, from: rerQuay(1)),
            train(rerA, to: "Boissy-Saint-Léger", inMinutes: 5, from: rerQuay(2)),
            train(rerA, to: "Marne-la-Vallée - Chessy", inMinutes: 9, from: rerQuay(2))
        ])

        #expect(result.map(\.label) == [west, east])
        #expect(result.map { $0.trains.map(\.destination) } == [
            ["Saint-Germain-en-Laye", "Poissy"],
            ["Boissy-Saint-Léger", "Marne-la-Vallée - Chessy"]
        ])
    }

    @Test func neverMakesAThirdDirectionFromAShortTripAtAStationOfTheTrunkOfAnyRERLine() {
        let rerC = TransitLine(mode: .rer, name: "C", stopIds: ["IDFM:monomodalStopPlace:1"])
        let rerD = TransitLine(mode: .rer, name: "D", stopIds: ["IDFM:monomodalStopPlace:2"])
        let rerE = TransitLine(mode: .rer, name: "E", stopIds: ["IDFM:monomodalStopPlace:3"])
        let cases: [(station: Station, departures: [Departure])] = [
            (station("Gare du Nord", [rerB]), [
                train(rerB, to: "Aéroport Charles de Gaulle 1", inMinutes: 1, from: rerQuay(3)),
                train(rerB, to: "Mitry - Claye", inMinutes: 2, from: rerQuay(1)),
                train(rerB, to: "Massy - Palaiseau", inMinutes: 3, from: rerQuay(4)),
                train(rerB, to: "Robinson", inMinutes: 4, from: rerQuay(2))
            ]),
            (station("Saint-Michel Notre-Dame", [rerC]), [
                train(rerC, to: "Versailles Chantiers", inMinutes: 1, from: rerQuay(3)),
                train(rerC, to: "Pontoise", inMinutes: 2, from: rerQuay(1)),
                train(rerC, to: "Juvisy", inMinutes: 3, from: rerQuay(4)),
                train(rerC, to: "Dourdan la Forêt", inMinutes: 4, from: rerQuay(2))
            ]),
            (station("Gare de Lyon", [rerD]), [
                train(rerD, to: "Orry-la-Ville - Coye", inMinutes: 1, from: rerQuay(3)),
                train(rerD, to: "Creil", inMinutes: 2, from: rerQuay(1)),
                train(rerD, to: "Corbeil-Essonnes", inMinutes: 3, from: rerQuay(4)),
                train(rerD, to: "Melun", inMinutes: 4, from: rerQuay(2))
            ]),
            (station("Magenta", [rerE]), [
                train(rerE, to: "Haussmann Saint-Lazare", inMinutes: 1, from: rerQuay(3)),
                train(rerE, to: "Nanterre-La-Folie", inMinutes: 2, from: rerQuay(1)),
                train(rerE, to: "Gagny", inMinutes: 3, from: rerQuay(4)),
                train(rerE, to: "Tournan", inMinutes: 4, from: rerQuay(2))
            ])
        ]

        let shown = cases.map { station, departures in
            let line = station.lines[0]
            return LineDirections.directions(of: line, at: station, from: departures, now: now)
                .map { $0.trains.map(\.destination) }
        }

        #expect(shown == [
            [["Aéroport Charles de Gaulle 1", "Mitry - Claye"], ["Massy - Palaiseau", "Robinson"]],
            [["Versailles Chantiers", "Pontoise"], ["Juvisy", "Dourdan la Forêt"]],
            [["Creil"], ["Corbeil-Essonnes", "Melun"]],
            [["Nanterre-La-Folie"], ["Gagny", "Tournan"]]
        ])
    }
}
