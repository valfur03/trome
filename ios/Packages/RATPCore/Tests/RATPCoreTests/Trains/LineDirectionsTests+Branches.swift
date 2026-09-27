import Foundation
import Testing
@testable import RATPCore

extension LineDirectionsTests {
    private var line7: TransitLine {
        TransitLine(mode: .metro, name: "7", stopIds: ["IDFM:70", "IDFM:71"])
    }

    private var line13: TransitLine {
        TransitLine(mode: .metro, name: "13", stopIds: ["IDFM:130", "IDFM:131"])
    }

    private var rerC: TransitLine {
        TransitLine(mode: .rer, name: "C", stopIds: ["IDFM:monomodalStopPlace:21"])
    }

    private func quay(_ code: Int) -> String {
        "STIF:StopPoint:Q:\(code):"
    }

    private func branchTrain(_ time: Double, to destination: String) -> LineDirection.Train {
        LineDirection.Train(time: self.time(inMinutes: time), destination: destination)
    }

    @Test func namesTheBranchOfEachTrainOfLine7BeforeTheFork() {
        let result = directions(of: line7, at: "Opéra", [
            train(line7, to: "Villejuif-Louis Aragon", inMinutes: 2, from: quay(71)),
            train(line7, to: "Mairie d'Ivry", inMinutes: 5, from: quay(71)),
            train(line7, to: "La Courneuve-8-Mai-1945", inMinutes: 3, from: quay(70))
        ])

        #expect(result == [
            LineDirection(label: "La Courneuve - 8 Mai 1945", times: [time(inMinutes: 3)]),
            LineDirection(label: "Mairie d'Ivry / Villejuif - Louis Aragon", trains: [
                branchTrain(2, to: "Villejuif - Louis Aragon"),
                branchTrain(5, to: "Mairie d'Ivry")
            ])
        ])
        #expect(result.map(\.showsEachDestination) == [false, true])
    }

    @Test func namesTheBranchOfEachTrainOfLine13BeforeTheFork() {
        let result = directions(of: line13, at: "Place de Clichy", [
            train(line13, to: "Asnières-Gennevilliers Les Courtilles", inMinutes: 1, from: quay(130)),
            train(line13, to: "Saint-Denis-Université", inMinutes: 4, from: quay(130)),
            train(line13, to: "Châtillon-Montrouge", inMinutes: 2, from: quay(131))
        ])

        #expect(result == [
            LineDirection(label: "Saint-Denis - Université / Asnières - Gennevilliers - Les Courtilles", trains: [
                branchTrain(1, to: "Asnières - Gennevilliers - Les Courtilles"),
                branchTrain(4, to: "Saint-Denis - Université")
            ]),
            LineDirection(label: "Châtillon - Montrouge", times: [time(inMinutes: 2)])
        ])
        #expect(result.map(\.showsEachDestination) == [true, false])
    }

    @Test func namesTheBranchOfBothTrainsOnceWhenBothGoToTheSameBranch() {
        let result = directions(of: line13, at: "Place de Clichy", [
            train(line13, to: "Saint-Denis-Université", inMinutes: 1, from: quay(130)),
            train(line13, to: "Saint-Denis-Université", inMinutes: 6, from: quay(130))
        ])

        #expect(result[0].trains == [
            branchTrain(1, to: "Saint-Denis - Université"),
            branchTrain(6, to: "Saint-Denis - Université")
        ])
        #expect(!result[0].showsEachDestination)
        #expect(result[0].name == "Saint-Denis - Université")
    }

    @Test func namesOnlyTheOwnBranchOfAStationAfterTheFork() {
        let brochant = directions(of: line13, at: "Brochant", [
            train(line13, to: "Asnières-Gennevilliers Les Courtilles", inMinutes: 1, from: quay(130))
        ])
        let porteDItalie = directions(of: line7, at: "Porte d'Italie", [])

        #expect(brochant == [
            LineDirection(label: "Asnières - Gennevilliers - Les Courtilles", times: [time(inMinutes: 1)]),
            LineDirection(label: "Châtillon - Montrouge", times: [])
        ])
        #expect(brochant.allSatisfy { !$0.showsEachDestination })
        #expect(brochant.map(\.name) == ["Asnières - Gennevilliers - Les Courtilles", "Châtillon - Montrouge"])
        #expect(porteDItalie.map(\.label) == ["La Courneuve - 8 Mai 1945", "Mairie d'Ivry"])
    }

    @Test func showsEachRERBDestinationUnderItsOwnName() {
        let result = directions(of: rerB, at: "Denfert-Rochereau", [
            train(rerB, to: "Saint-Rémy-lès-Chevreuse", inMinutes: 1),
            train(rerB, to: "Robinson", inMinutes: 2),
            train(rerB, to: "Saint-Rémy-lès-Chevreuse", inMinutes: 8)
        ])

        #expect(result == [
            LineDirection(label: "Saint-Rémy-lès-Chevreuse", times: [time(inMinutes: 1), time(inMinutes: 8)]),
            LineDirection(label: "Robinson", times: [time(inMinutes: 2)])
        ])
    }

    @Test func showsEachRERCDestinationUnderItsOwnName() {
        let result = directions(of: rerC, at: "Saint-Michel Notre-Dame", [
            train(rerC, to: "Versailles Château Rive Gauche", inMinutes: 3),
            train(rerC, to: "Pontoise", inMinutes: 4),
            train(rerC, to: "Dourdan", inMinutes: 6),
            train(rerC, to: "Versailles Château Rive Gauche", inMinutes: 12)
        ])

        #expect(result == [
            LineDirection(label: "Versailles Château Rive Gauche", times: [time(inMinutes: 3), time(inMinutes: 12)]),
            LineDirection(label: "Pontoise", times: [time(inMinutes: 4)]),
            LineDirection(label: "Dourdan", times: [time(inMinutes: 6)])
        ])
    }

    @Test func namesTheDestinationOfTrainsThatEndBeforeTheEndOfLine() {
        let result = directions(of: line13, at: "Place de Clichy", [
            train(line13, to: "Saint-Ouen", inMinutes: 2, from: quay(130)),
            train(line13, to: "Gare Saint-Lazare", inMinutes: 3, from: quay(131)),
            train(line13, to: "Saint-Denis-Université", inMinutes: 5, from: quay(130))
        ])

        #expect(result.map(\.label) == [
            "Saint-Denis - Université / Asnières - Gennevilliers - Les Courtilles",
            "Châtillon - Montrouge"
        ])
        #expect(result[0].trains == [
            branchTrain(2, to: "Saint-Ouen"),
            branchTrain(5, to: "Saint-Denis - Université")
        ])
        #expect(result[1].trains == [branchTrain(3, to: "Gare Saint-Lazare")])
        #expect(result.map(\.showsEachDestination) == [true, false])
        #expect(result.map(\.name) == [
            "Saint-Denis - Université / Asnières - Gennevilliers - Les Courtilles",
            "Gare Saint-Lazare"
        ])
    }

    @Test func namesEveryBranchStationAsAStationOfItsLine() throws {
        let catalog = try StationCatalog.bundled()

        for name in ["7", "13"] {
            let ends = try #require(TransitLine(mode: .metro, name: name).ends)
            #expect(!ends.branchStations.isEmpty)
            for (end, stations) in ends.branchStations {
                #expect(ends.sides.contains { $0.count > 1 && $0.contains(end) })
                for stationName in stations {
                    let served = catalog.stations.contains { station in
                        station.name == stationName && station.lines.contains { $0.mode == .metro && $0.name == name }
                    }
                    #expect(served, "\(stationName) is not a station of metro \(name)")
                }
            }
        }
    }
}
