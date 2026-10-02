import Foundation
import Testing
@testable import RATPCore

extension LineDirectionsTests {
    private var metro6: TransitLine {
        TransitLine(mode: .metro, name: "6", stopIds: ["IDFM:10", "IDFM:11"])
    }

    private var rerD: TransitLine {
        TransitLine(mode: .rer, name: "D", stopIds: ["IDFM:monomodalStopPlace:43092"])
    }

    private func directions(
        of line: TransitLine,
        at stationName: String,
        _ departures: [Departure],
        later laterDepartures: [Departure]
    ) -> [LineDirection] {
        LineDirections.directions(
            of: line,
            at: station(stationName, [line]),
            from: departures,
            later: laterDepartures,
            now: now
        )
    }

    @Test func saysTheNextTrainIsOverAnHourAwayForADirectionWhoseTrainsAreAllLater() {
        let result = directions(of: metro6, at: "Chevaleret", [
            train(metro6, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:11:")
        ], later: [
            train(metro6, to: "Charles de Gaulle - Étoile", inMinutes: 65, from: "STIF:StopPoint:Q:10:"),
            train(metro6, to: "Nation", inMinutes: 70, from: "STIF:StopPoint:Q:11:")
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: [], nextTrainIsOverAnHourAway: true),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
    }

    @Test func keepsSayingNoTrainsForADirectionWithoutAnyTrain() {
        let result = directions(of: metro6, at: "Chevaleret", [
            train(metro6, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:11:")
        ], later: [
            train(metro6, to: "Nation", inMinutes: 70, from: "STIF:StopPoint:Q:11:")
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: []),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
    }

    @Test func showsTheOnlyDirectionOfAStationWithOneQuayWhenItsTrainsAreAllLater() {
        let line10 = TransitLine(mode: .metro, name: "10", stopIds: ["IDFM:40"])

        let result = directions(of: line10, at: "Mirabeau", [], later: [
            train(line10, to: "Boulogne-Pont de Saint-Cloud", inMinutes: 62, from: "STIF:StopPoint:Q:40:")
        ])

        #expect(result == [
            LineDirection(label: "Boulogne Pont de Saint-Cloud", times: [], nextTrainIsOverAnHourAway: true)
        ])
    }

    @Test func keepsTheTwoEndsOfADirectionWhoseTrainsAreAllLater() {
        let line13 = TransitLine(mode: .metro, name: "13", stopIds: ["IDFM:130"])
        let ends = ["Saint-Denis - Université", "Asnières - Gennevilliers - Les Courtilles"]

        let result = directions(of: line13, at: "Liège", [], later: [
            train(line13, to: "Saint-Denis-Université", inMinutes: 62, from: "STIF:StopPoint:Q:130:")
        ])

        #expect(result == [
            LineDirection(
                label: ends.joined(separator: " / "),
                trains: [],
                nextTrainIsOverAnHourAway: true,
                branchEnds: ends,
                trainsOfEachEnd: [
                    BranchEndTrains(end: ends[0], trains: [], nextTrainIsOverAnHourAway: true),
                    BranchEndTrains(end: ends[1], trains: [])
                ]
            )
        ])
    }

    @Test func showsADestinationOfAnUnknownDirectionWhenItsTrainsAreAllLater() {
        let result = directions(of: metro6, at: "Chevaleret", [
            train(metro6, to: "Nation", inMinutes: 2, from: "STIF:StopPoint:Q:11:"),
            train(metro6, to: "Charles de Gaulle - Étoile", inMinutes: 3, from: "STIF:StopPoint:Q:10:")
        ], later: [
            train(metro6, to: "Trocadéro", inMinutes: 64)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: [time(inMinutes: 3)]),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)]),
            LineDirection(label: "Trocadéro", times: [], nextTrainIsOverAnHourAway: true)
        ])
    }

    @Test func neverDropsADirectionWithTrainsToShowADirectionWhoseTrainsAreAllLater() {
        let unknownLine = TransitLine(mode: .rer, name: "Z", stopIds: ["IDFM:monomodalStopPlace:90"])
        let departures = [
            train(unknownLine, to: "West", inMinutes: 5),
            train(unknownLine, to: "North", inMinutes: 3),
            train(unknownLine, to: "East", inMinutes: 1)
        ]

        let result = directions(of: unknownLine, at: "Somewhere", departures, later: [
            train(unknownLine, to: "South", inMinutes: 61),
            train(unknownLine, to: "North", inMinutes: 75)
        ])

        #expect(result == directions(of: unknownLine, at: "Somewhere", departures))
    }

    @Test func saysTheNextTrainToMalesherbesIsOverAnHourAwayAtBoignevilleRightAfterOneLeaves() {
        let result = directions(of: rerD, at: "Boigneville", [
            train(rerD, to: "Creil", inMinutes: 12),
            train(rerD, to: "Creil", inMinutes: 42)
        ], later: [
            train(rerD, to: "Malesherbes", inMinutes: 65)
        ])

        #expect(result.map(\.times) == [[time(inMinutes: 12), time(inMinutes: 42)], []])
        #expect(result.map(\.nextTrainIsOverAnHourAway) == [false, true])
        #expect(result[1].name == "Malesherbes")
    }
}
