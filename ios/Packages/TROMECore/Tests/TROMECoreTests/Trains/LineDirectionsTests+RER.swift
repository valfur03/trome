import Foundation
import Testing
@testable import TROMECore

extension LineDirectionsTests {
    private var rerA: TransitLine {
        TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:45102"])
    }

    private var rerE: TransitLine {
        TransitLine(mode: .rer, name: "E", stopIds: ["IDFM:monomodalStopPlace:22"])
    }

    private func rerTrain(_ time: Double, to destination: String) -> LineDirection.Train {
        LineDirection.Train(time: self.time(inMinutes: time), destination: destination)
    }

    @Test func showsBothDirectionsOfRERBWhenTheSoonestTrainsAllGoTheSameWay() {
        let result = directions(of: rerB, at: "Châtelet - Les Halles", [
            train(rerB, to: "Aéroport Charles de Gaulle 2 (Terminal 2)", inMinutes: 1, from: rerQuay(1)),
            train(rerB, to: "Mitry - Claye", inMinutes: 2, from: rerQuay(2)),
            train(rerB, to: "Aéroport Charles de Gaulle 2 (Terminal 2)", inMinutes: 4, from: rerQuay(1)),
            train(rerB, to: "Saint-Rémy-lès-Chevreuse", inMinutes: 9, from: rerQuay(3))
        ])

        #expect(result == [
            LineDirection(label: "Aéroport Charles de Gaulle 2 TGV / Mitry - Claye", trains: [
                rerTrain(1, to: "Aéroport Charles de Gaulle 2"),
                rerTrain(2, to: "Mitry - Claye")
            ]),
            LineDirection(label: "Robinson / Saint-Rémy-lès-Chevreuse", trains: [
                rerTrain(9, to: "Saint-Rémy-lès-Chevreuse")
            ])
        ])
        #expect(result.map(\.showsEachDestination) == [true, false])
    }

    @Test func showsBothDirectionsOfRERAAtChateletFromARecordedAnswer() throws {
        let station = Station(
            id: "IDFM:monomodalStopPlace:45102",
            name: "Châtelet - Les Halles",
            coordinate: Coordinate(48.861745, 2.346977),
            lines: [rerA, TransitLine(mode: .rer, name: "B", stopIds: ["IDFM:monomodalStopPlace:45102"])]
        )
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-chatelet-rer"))
        let departures = PRIMDeparturesProvider.departures(from: visits, at: [station])

        let result = LineDirections.directions(of: rerA, at: station, from: departures, now: now)

        #expect(result == [
            LineDirection(label: "Saint-Germain-en-Laye / Cergy le Haut / Poissy", trains: [
                LineDirection.Train(time: Fixture.date("2026-09-27T08:03:00Z"), destination: "Saint-Germain-en-Laye")
            ]),
            LineDirection(label: "Boissy-Saint-Léger / Marne-la-Vallée - Chessy", trains: [
                LineDirection.Train(time: Fixture.date("2026-09-27T08:02:00Z"), destination: "Boissy-Saint-Léger")
            ])
        ])
    }

    @Test func namesEachRERTrainOfOneDirectionThatEndsAtADifferentPlace() {
        let result = directions(of: rerB, at: "Gare du Nord", [
            train(rerB, to: "Massy-Palaiseau", inMinutes: 1, from: rerQuay(3)),
            train(rerB, to: "Robinson", inMinutes: 5, from: rerQuay(3)),
            train(rerB, to: "Mitry - Claye", inMinutes: 3, from: rerQuay(1))
        ])

        #expect(result[1].trains == [rerTrain(1, to: "Massy-Palaiseau"), rerTrain(5, to: "Robinson")])
        #expect(result.map(\.showsEachDestination) == [false, true])
    }

    @Test func showsNoTrainsForAnRERDirectionWithoutTrains() {
        let result = directions(of: rerA, at: "Nation", [
            train(rerA, to: "Boissy-Saint-Léger", inMinutes: 2, from: rerQuay(1)),
            train(rerA, to: "Marne-la-Vallée Chessy", inMinutes: 4, from: rerQuay(1))
        ])

        #expect(result == [
            LineDirection(label: "Saint-Germain-en-Laye / Cergy le Haut / Poissy", times: []),
            LineDirection(label: "Boissy-Saint-Léger / Marne-la-Vallée - Chessy", trains: [
                rerTrain(2, to: "Boissy-Saint-Léger"),
                rerTrain(4, to: "Marne-la-Vallée - Chessy")
            ])
        ])
    }

    @Test func usesTheDirectionOfATrainWhenItsQuayHasOnlyTrainsThatEndBeforeTheEndOfLine() {
        let result = directions(of: rerB, at: "Denfert-Rochereau", [
            train(rerB, to: "Gare du Nord", inMinutes: 1, from: rerQuay(2), direction: "Retour"),
            train(rerB, to: "Massy-Palaiseau", inMinutes: 2, from: rerQuay(4), direction: "Aller"),
            train(rerB, to: "Mitry - Claye", inMinutes: 3, from: rerQuay(1), direction: "Retour"),
            train(rerB, to: "Robinson", inMinutes: 4, from: rerQuay(3), direction: "Aller")
        ])

        #expect(result.map(\.trains) == [
            [rerTrain(1, to: "Gare du Nord"), rerTrain(3, to: "Mitry - Claye")],
            [rerTrain(2, to: "Massy-Palaiseau"), rerTrain(4, to: "Robinson")]
        ])
    }

    @Test func neverPutsATrainOfAnUnknownRERQuayInTheOnlyDirectionWithoutTrains() {
        let result = directions(of: rerB, at: "Denfert-Rochereau", [
            train(rerB, to: "Mitry - Claye", inMinutes: 2, from: rerQuay(1)),
            train(rerB, to: "Gare du Nord", inMinutes: 4, from: rerQuay(2))
        ])

        #expect(result == [
            LineDirection(label: "Aéroport Charles de Gaulle 2 TGV / Mitry - Claye", trains: [
                rerTrain(2, to: "Mitry - Claye")
            ]),
            LineDirection(label: "Robinson / Saint-Rémy-lès-Chevreuse", times: [])
        ])
    }

    @Test func ignoresATrainDirectionThatIsTheSameForBothWays() {
        let result = directions(of: rerA, at: "Sartrouville", [
            train(rerA, to: "Houilles - Carrières-sur-Seine", inMinutes: 1, from: rerQuay(4), direction: "Aller"),
            train(rerA, to: "Boissy-Saint-Léger", inMinutes: 2, from: rerQuay(1), direction: "Aller"),
            train(rerA, to: "Cergy le Haut", inMinutes: 3, from: rerQuay(2), direction: "Aller")
        ])

        #expect(result == [
            LineDirection(label: "Cergy le Haut / Poissy", trains: [rerTrain(3, to: "Cergy le Haut")]),
            LineDirection(label: "Boissy-Saint-Léger / Marne-la-Vallée - Chessy", trains: [
                rerTrain(2, to: "Boissy-Saint-Léger")
            ]),
            LineDirection(label: "Houilles - Carrières-sur-Seine", times: [time(inMinutes: 1)])
        ])
    }

    @Test func putsRERTrainsWithoutQuayInTheDirectionOfTheirEndOfLine() {
        let result = directions(of: rerE, at: "Magenta", [
            train(rerE, to: "Tournan", inMinutes: 1),
            train(rerE, to: "Chelles Gournay", inMinutes: 4),
            train(rerE, to: "Nanterre-La-Folie", inMinutes: 6)
        ])

        #expect(result == [
            LineDirection(label: "Nanterre-La-Folie", times: [time(inMinutes: 6)]),
            LineDirection(label: "Chelles - Gournay / Tournan", trains: [
                rerTrain(1, to: "Tournan"),
                rerTrain(4, to: "Chelles - Gournay")
            ])
        ])
    }

    @Test func namesOnlyTheRERBranchEndsThatAStationCanReach() {
        let sartrouville = directions(of: rerA, at: "Sartrouville", [])
        let massy = directions(of: rerB, at: "Massy - Palaiseau", [])
        let moulinGalant = directions(
            of: TransitLine(mode: .rer, name: "D", stopIds: ["IDFM:monomodalStopPlace:43097"]),
            at: "Moulin Galant",
            []
        )

        #expect(sartrouville.map(\.label) == [
            "Cergy le Haut / Poissy",
            "Boissy-Saint-Léger / Marne-la-Vallée - Chessy"
        ])
        #expect(massy.map(\.label) == ["Aéroport Charles de Gaulle 2 TGV / Mitry - Claye", "Saint-Rémy-lès-Chevreuse"])
        #expect(moulinGalant.map(\.label) == ["Creil", "Malesherbes"])
    }

    @Test func putsATrainToAStationBeforeTheForkInTheOtherDirectionOfARERBranch() {
        let rerD = TransitLine(mode: .rer, name: "D", stopIds: ["IDFM:monomodalStopPlace:43090"])
        let result = directions(of: rerD, at: "Boigneville", [
            train(rerD, to: "Malesherbes", inMinutes: 23, from: rerQuay(1)),
            train(rerD, to: "Paris Gare de Lyon", inMinutes: 47, from: rerQuay(2))
        ])

        #expect(result == [
            LineDirection(label: "Creil", trains: [rerTrain(47, to: "Paris Gare de Lyon")]),
            LineDirection(label: "Malesherbes", trains: [rerTrain(23, to: "Malesherbes")])
        ])
        #expect(result.map(\.name) == ["Paris Gare de Lyon", "Malesherbes"])
    }

    @Test func putsATrainToTheSharedPartOfTwoRERBranchesInTheOtherDirection() {
        let rerD = TransitLine(mode: .rer, name: "D", stopIds: ["IDFM:monomodalStopPlace:43092"])
        let result = directions(of: rerD, at: "Saint-Fargeau", [
            train(rerD, to: "Melun", inMinutes: 12, from: rerQuay(1)),
            train(rerD, to: "Corbeil-Essonnes", inMinutes: 18, from: rerQuay(2))
        ])

        #expect(result == [
            LineDirection(label: "Creil", trains: [rerTrain(18, to: "Corbeil-Essonnes")]),
            LineDirection(label: "Melun", trains: [rerTrain(12, to: "Melun")])
        ])
    }

    @Test func neverGuessesTheDirectionOfATrainToAStationOfAnotherBranchOfTheSameRERSide() {
        let rerC = TransitLine(mode: .rer, name: "C", stopIds: ["IDFM:monomodalStopPlace:43091"])
        let result = directions(of: rerC, at: "Orly Ville", [
            train(rerC, to: "Juvisy", inMinutes: 5, from: rerQuay(1)),
            train(rerC, to: "Paris Austerlitz", inMinutes: 8, from: rerQuay(2))
        ])

        #expect(result.map(\.label) == [
            "Pontoise / Versailles Château Rive Gauche / Saint-Quentin en Yvelines - Montigny-le-Bretonneux",
            "Massy - Palaiseau",
            "Juvisy"
        ])
    }

    @Test func neverGuessesTheDirectionOfATrainToAStationOfAnRERBranch() {
        let rerC = TransitLine(mode: .rer, name: "C", stopIds: ["IDFM:monomodalStopPlace:43091"])
        let result = directions(of: rerC, at: "Orly Ville", [
            train(rerC, to: "Versailles Chantiers", inMinutes: 5, from: rerQuay(1)),
            train(rerC, to: "Paris Austerlitz", inMinutes: 8, from: rerQuay(2))
        ])

        #expect(result.map(\.label) == [
            "Pontoise / Versailles Château Rive Gauche / Saint-Quentin en Yvelines - Montigny-le-Bretonneux",
            "Massy - Palaiseau",
            "Versailles Chantiers"
        ])
        #expect(result.map(\.trains) == [
            [rerTrain(8, to: "Paris Austerlitz")],
            [],
            [rerTrain(5, to: "Versailles Chantiers")]
        ])
    }

    @Test func showsOnlyTheOtherDirectionAtAnRERTerminus() {
        let result = directions(of: rerB, at: "Robinson", [
            train(rerB, to: "Aéroport Charles de Gaulle 2 (Terminal 2)", inMinutes: 3, from: rerQuay(1))
        ])

        #expect(result == [
            LineDirection(label: "Aéroport Charles de Gaulle 2 TGV / Mitry - Claye", trains: [
                rerTrain(3, to: "Aéroport Charles de Gaulle 2")
            ])
        ])
    }
}
