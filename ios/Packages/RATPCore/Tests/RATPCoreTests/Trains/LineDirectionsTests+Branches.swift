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
            ], branchEnds: ["Mairie d'Ivry", "Villejuif - Louis Aragon"], trainsOfEachEnd: [
                BranchEndTrains(end: "Mairie d'Ivry", trains: [branchTrain(5, to: "Mairie d'Ivry")]),
                BranchEndTrains(
                    end: "Villejuif - Louis Aragon",
                    trains: [branchTrain(2, to: "Villejuif - Louis Aragon")]
                )
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
            ], branchEnds: ["Saint-Denis - Université", "Asnières - Gennevilliers - Les Courtilles"], trainsOfEachEnd: [
                BranchEndTrains(
                    end: "Saint-Denis - Université",
                    trains: [branchTrain(4, to: "Saint-Denis - Université")]
                ),
                BranchEndTrains(
                    end: "Asnières - Gennevilliers - Les Courtilles",
                    trains: [branchTrain(1, to: "Asnières - Gennevilliers - Les Courtilles")]
                )
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

    @Test func putsATrainToAStationBeforeTheForkInTheOtherDirectionOfABranch() {
        let result = directions(of: line13, at: "Brochant", [
            train(line13, to: "Gare Saint-Lazare", inMinutes: 2, from: quay(132)),
            train(line13, to: "Asnières-Gennevilliers Les Courtilles", inMinutes: 4, from: quay(130))
        ])

        #expect(result == [
            LineDirection(label: "Asnières - Gennevilliers - Les Courtilles", times: [time(inMinutes: 4)]),
            LineDirection(label: "Châtillon - Montrouge", trains: [branchTrain(2, to: "Gare Saint-Lazare")])
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

    @Test(arguments: [
        TransitLine(mode: .metro, name: "7"),
        TransitLine(mode: .metro, name: "13"),
        TransitLine(mode: .rer, name: "A"),
        TransitLine(mode: .rer, name: "B"),
        TransitLine(mode: .rer, name: "C"),
        TransitLine(mode: .rer, name: "D"),
        TransitLine(mode: .rer, name: "E")
    ])
    func namesEveryBranchStationAsAStationOfItsLine(line: TransitLine) throws {
        let catalog = try StationCatalog.bundled()
        let ends = try #require(line.ends)

        #expect(!ends.branchStations.isEmpty)
        for (end, stations) in ends.branchStations {
            #expect(ends.sides.contains { $0.count > 1 && $0.contains(end) })
            for stationName in stations {
                let served = catalog.stations.contains { station in
                    station.name == stationName
                        && station.lines.contains { $0.mode == line.mode && $0.name == line.name }
                }
                #expect(served, "\(stationName) is not a station of \(line.displayName)")
            }
        }
    }

    @Test func givesOneRowToEachBranchWithItsOwnTrains() {
        let direction = LineDirection(label: "Mairie d'Ivry / Villejuif - Louis Aragon", trains: [
            branchTrain(2, to: "Villejuif - Louis Aragon"),
            branchTrain(5, to: "Mairie d'Ivry"),
            branchTrain(7, to: "Villejuif - Louis Aragon")
        ])

        #expect(direction.trainsByDestination == [
            DestinationTrains(destination: "Villejuif - Louis Aragon", trains: [
                branchTrain(2, to: "Villejuif - Louis Aragon"),
                branchTrain(7, to: "Villejuif - Louis Aragon")
            ]),
            DestinationTrains(destination: "Mairie d'Ivry", trains: [branchTrain(5, to: "Mairie d'Ivry")])
        ])
    }

    @Test func givesOneRowToADirectionWhoseTrainsAllGoToOnePlaceOrWithoutTrains() {
        let oneBranch = LineDirection(label: "Mairie d'Ivry / Villejuif - Louis Aragon", trains: [
            branchTrain(2, to: "Mairie d'Ivry"),
            branchTrain(5, to: "Mairie d'Ivry")
        ])
        let empty = LineDirection(label: "La Courneuve - 8 Mai 1945", trains: [])

        #expect(oneBranch.trainsByDestination == [
            DestinationTrains(destination: "Mairie d'Ivry", trains: oneBranch.trains)
        ])
        #expect(empty.trainsByDestination == [DestinationTrains(destination: "La Courneuve - 8 Mai 1945", trains: [])])
    }
}
