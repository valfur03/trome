import Foundation
import Testing
@testable import RATPCore

struct LineDirectionsTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line6 = TransitLine(mode: .metro, name: "6", stopIds: ["IDFM:10", "IDFM:11"])
    private let westQuay = "STIF:StopPoint:Q:10:"
    private let eastQuay = "STIF:StopPoint:Q:11:"
    private let rerB = TransitLine(mode: .rer, name: "B", stopIds: ["IDFM:monomodalStopPlace:20"])

    private func station(_ name: String, _ lines: [TransitLine]) -> Station {
        Station(id: name, name: name, coordinate: Coordinate(48.85, 2.35), lines: lines)
    }

    private func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    private func train(
        _ line: TransitLine,
        to destination: String,
        inMinutes minutes: Double,
        from quay: String? = nil
    ) -> Departure {
        Departure(line: line, destination: destination, time: time(inMinutes: minutes), quayRef: quay)
    }

    private func directions(
        of line: TransitLine,
        at stationName: String,
        _ departures: [Departure]
    ) -> [LineDirection] {
        LineDirections.directions(of: line, at: station(stationName, [line]), from: departures)
    }

    @Test func labelsEachDirectionWithItsEndOfLine() {
        let result = directions(of: line6, at: "Chevaleret", [
            train(line6, to: "Nation", inMinutes: 2, from: eastQuay),
            train(line6, to: "Charles de Gaulle-Etoile", inMinutes: 4, from: westQuay)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: [time(inMinutes: 4)]),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
    }

    @Test func showsNoTrainsForADirectionWithoutTrains() {
        let result = directions(of: line6, at: "Chevaleret", [train(line6, to: "Nation", inMinutes: 2, from: eastQuay)])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: []),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
    }

    @Test func putsATrainThatEndsBeforeTheEndOfLineInTheDirectionOfItsQuay() {
        let result = directions(of: line6, at: "Chevaleret", [
            train(line6, to: "Trocadéro", inMinutes: 1, from: westQuay),
            train(line6, to: "Nation", inMinutes: 2, from: eastQuay)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: [time(inMinutes: 1)]),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
    }

    @Test func showsTrainsOfAnUnknownDirectionUnderTheirDestination() {
        let result = directions(of: line6, at: "Chevaleret", [
            train(line6, to: "Trocadéro", inMinutes: 1, from: westQuay)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: []),
            LineDirection(label: "Nation", times: []),
            LineDirection(label: "Trocadéro", times: [time(inMinutes: 1)])
        ])
    }

    @Test func matchesADestinationNameWithExtraWords() {
        let line1 = TransitLine(mode: .metro, name: "1", stopIds: ["IDFM:30", "IDFM:31"])

        let result = directions(of: line1, at: "Bérault", [
            train(line1, to: "La Défense (Grande Arche)", inMinutes: 3, from: "STIF:StopPoint:Q:30:")
        ])

        #expect(result == [
            LineDirection(label: "La Défense", times: [time(inMinutes: 3)]),
            LineDirection(label: "Château de Vincennes", times: [])
        ])
    }

    @Test func showsOnlyTheOtherDirectionAtTheEndOfTheLine() {
        let result = directions(of: line6, at: "Nation", [
            train(line6, to: "Charles de Gaulle - Étoile", inMinutes: 6, from: eastQuay),
            train(line6, to: "Charles de Gaulle - Étoile", inMinutes: 3, from: westQuay),
            train(line6, to: "Trocadéro", inMinutes: 1, from: westQuay)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: [time(inMinutes: 1), time(inMinutes: 3)])
        ])
    }

    @Test func showsOnlyTheDirectionOfAStationWithOneQuay() {
        let line10 = TransitLine(mode: .metro, name: "10", stopIds: ["IDFM:40"])

        let result = directions(of: line10, at: "Mirabeau", [
            train(line10, to: "Boulogne-Pont de Saint-Cloud", inMinutes: 2, from: "STIF:StopPoint:Q:40:")
        ])

        #expect(result == [LineDirection(label: "Boulogne Pont de Saint-Cloud", times: [time(inMinutes: 2)])])
        #expect(directions(of: line10, at: "Mirabeau", []).isEmpty)
    }

    @Test func showsAtMostTwoTrainsInEachDirection() {
        let result = directions(of: line6, at: "Chevaleret", [1, 4, 8].map {
            train(line6, to: "Nation", inMinutes: $0, from: eastQuay)
        })

        #expect(result.last == LineDirection(label: "Nation", times: [time(inMinutes: 1), time(inMinutes: 4)]))
    }

    @Test func showsTheSoonestDestinationsOfALineWithoutKnownEnds() {
        let result = directions(of: rerB, at: "Gare du Nord", [
            train(rerB, to: "Robinson", inMinutes: 5),
            train(rerB, to: "Mitry-Claye", inMinutes: 3),
            train(rerB, to: "Aéroport Charles de Gaulle 2", inMinutes: 1),
            train(rerB, to: "Massy-Palaiseau", inMinutes: 7),
            train(rerB, to: "Mitry-Claye", inMinutes: 9)
        ])

        #expect(result == [
            LineDirection(label: "Aéroport Charles de Gaulle 2", times: [time(inMinutes: 1)]),
            LineDirection(label: "Mitry-Claye", times: [time(inMinutes: 3), time(inMinutes: 9)]),
            LineDirection(label: "Robinson", times: [time(inMinutes: 5)])
        ])
    }

    @Test func ignoresTheTrainsOfOtherLines() {
        let result = directions(of: line6, at: "Chevaleret", [train(rerB, to: "Nation", inMinutes: 2)])

        #expect(result.allSatisfy { $0.times.isEmpty })
    }

    @Test func namesEveryEndOfLineAsAStationOfThatLine() throws {
        let catalog = try StationCatalog.bundled()
        let metroNames = ["1", "2", "3", "3bis", "4", "5", "6", "7", "7bis", "8", "9", "10", "11", "12", "13", "14"]

        for name in metroNames {
            let ends = try #require(TransitLine(mode: .metro, name: name).ends)
            for end in ends.first + ends.second {
                let served = catalog.stations.contains { station in
                    station.name == end && station.lines.contains { $0.mode == .metro && $0.name == name }
                }
                #expect(served, "\(end) is not a station of metro \(name)")
            }
        }
    }
}
