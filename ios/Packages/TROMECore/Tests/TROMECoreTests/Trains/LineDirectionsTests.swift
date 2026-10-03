import Foundation
import Testing
@testable import TROMECore

struct LineDirectionsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    private let line6 = TransitLine(mode: .metro, name: "6", stopIds: ["IDFM:10", "IDFM:11"])
    private let westQuay = "STIF:StopPoint:Q:10:"
    private let eastQuay = "STIF:StopPoint:Q:11:"
    let rerB = TransitLine(mode: .rer, name: "B", stopIds: ["IDFM:monomodalStopPlace:20"])

    func station(_ name: String, _ lines: [TransitLine]) -> Station {
        Station(id: name, name: name, coordinate: Coordinate(48.85, 2.35), lines: lines)
    }

    func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    func train(
        _ line: TransitLine,
        to destination: String,
        inMinutes minutes: Double,
        from quay: String? = nil,
        direction: String? = nil,
        atStop: Bool = false
    ) -> Departure {
        Departure(
            line: line,
            destination: destination,
            time: time(inMinutes: minutes),
            quayRef: quay,
            directionRef: direction,
            isAtStop: atStop
        )
    }

    func directions(
        of line: TransitLine,
        at stationName: String,
        _ departures: [Departure]
    ) -> [LineDirection] {
        LineDirections.directions(of: line, at: station(stationName, [line]), from: departures, now: now)
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
        #expect(result.allSatisfy { !$0.showsEachDestination })
        #expect(result.map(\.name) == ["Charles de Gaulle - Étoile", "Nation"])
    }

    @Test func tellsWhichTrainIsApproachingOrAtThePlatform() {
        let result = directions(of: line6, at: "Chevaleret", [
            train(line6, to: "Nation", inMinutes: 0.5, from: eastQuay, atStop: true),
            train(line6, to: "Nation", inMinutes: 4, from: eastQuay),
            train(line6, to: "Charles de Gaulle-Etoile", inMinutes: 0.75, from: westQuay)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", trains: [
                LineDirection.Train(
                    time: time(inMinutes: 0.75),
                    destination: "Charles de Gaulle - Étoile",
                    status: .approaching
                )
            ]),
            LineDirection(label: "Nation", trains: [
                LineDirection.Train(time: time(inMinutes: 0.5), destination: "Nation", status: .atPlatform),
                LineDirection.Train(time: time(inMinutes: 4), destination: "Nation")
            ])
        ])
    }

    @Test func roundsTheWaitUpToTheNextWholeMinuteSoItNeverSaysZeroBeforeTheTrainLeaves() {
        let train = LineDirection.Train(time: time(inMinutes: 3), destination: "Nation")

        let minutes = [2.75, 2.5, 1.9, 1.25, 0.5, 0.01].map { minutesLeft in
            DepartureTime.minutes(until: train.roundedUpCountdownEnd, from: time(inMinutes: 3 - minutesLeft))
        }

        #expect(minutes == [3, 3, 2, 2, 1, 1])
    }

    @Test func countsTheMinutesThatTheLiveActivityTimerShowsNeverZero() {
        let train = LineDirection.Train(time: time(inMinutes: 10), destination: "Nation")

        let minutes = [10.5, 9.99, 9, 8.99, 2.99, 0.01, -0.5].map { minutesLeft in
            train.countdownMinutes(at: time(inMinutes: 10 - minutesLeft))
        }

        #expect(minutes == [11, 10, 10, 9, 3, 1, 1])
    }

    @Test func showsNoTrainsForADirectionWithoutTrains() {
        let result = directions(of: line6, at: "Chevaleret", [train(line6, to: "Nation", inMinutes: 2, from: eastQuay)])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", times: []),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
        #expect(result[0].name == "Charles de Gaulle - Étoile")
    }

    @Test func putsATrainThatEndsBeforeTheEndOfLineInTheDirectionOfItsQuay() {
        let result = directions(of: line6, at: "Chevaleret", [
            train(line6, to: "Trocadéro", inMinutes: 1, from: westQuay),
            train(line6, to: "Nation", inMinutes: 2, from: eastQuay)
        ])

        #expect(result == [
            LineDirection(label: "Charles de Gaulle - Étoile", trains: [
                LineDirection.Train(time: time(inMinutes: 1), destination: "Trocadéro")
            ]),
            LineDirection(label: "Nation", times: [time(inMinutes: 2)])
        ])
        #expect(!result[0].showsEachDestination)
        #expect(result.map(\.name) == ["Trocadéro", "Nation"])
    }

    @Test func showsTrainsOfAnUnknownDirectionUnderTheirDestinationAndNoEmptyDirection() {
        let result = directions(of: line6, at: "Chevaleret", [
            train(line6, to: "Trocadéro", inMinutes: 1, from: westQuay)
        ])

        #expect(result == [
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
            LineDirection(label: "Charles de Gaulle - Étoile", trains: [
                LineDirection.Train(time: time(inMinutes: 1), destination: "Trocadéro"),
                LineDirection.Train(time: time(inMinutes: 3), destination: "Charles de Gaulle - Étoile")
            ])
        ])
        #expect(result[0].showsEachDestination)
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
        let unknownLine = TransitLine(mode: .rer, name: "Z", stopIds: ["IDFM:monomodalStopPlace:90"])

        let result = directions(of: unknownLine, at: "Somewhere", [
            train(unknownLine, to: "West", inMinutes: 5),
            train(unknownLine, to: "North", inMinutes: 3),
            train(unknownLine, to: "East", inMinutes: 1),
            train(unknownLine, to: "South", inMinutes: 7),
            train(unknownLine, to: "North", inMinutes: 9)
        ])

        #expect(result == [
            LineDirection(label: "East", times: [time(inMinutes: 1)]),
            LineDirection(label: "North", times: [time(inMinutes: 3), time(inMinutes: 9)]),
            LineDirection(label: "West", times: [time(inMinutes: 5)])
        ])
    }

    @Test func ignoresTheTrainsOfOtherLines() {
        let result = directions(of: line6, at: "Chevaleret", [train(rerB, to: "Nation", inMinutes: 2)])

        #expect(result.allSatisfy { $0.times.isEmpty })
    }

    @Test func namesEveryEndOfLineAsAStationOfThatLine() throws {
        let catalog = try StationCatalog.bundled()
        let metroNames = ["1", "2", "3", "3bis", "4", "5", "6", "7", "7bis", "8", "9", "10", "11", "12", "13", "14"]
        let lines = metroNames.map { TransitLine(mode: .metro, name: $0) }
            + ["A", "B", "C", "D", "E"].map { TransitLine(mode: .rer, name: $0) }

        for line in lines {
            let ends = try #require(line.ends)
            for end in ends.first + ends.second {
                let served = catalog.stations.contains { station in
                    station.name == end && station.lines.contains { $0.mode == line.mode && $0.name == line.name }
                }
                #expect(served, "\(end) is not a station of \(line.displayName)")
            }
        }
    }
}
