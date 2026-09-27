import Foundation
import Testing
@testable import RATPCore

struct DepartureBoardTests {
    private let line1 = TransitLine(mode: .metro, name: "1")
    private let rerA = TransitLine(mode: .rer, name: "A")
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func station(_ name: String, _ lines: TransitLine...) -> Station {
        Station(id: name, name: name, coordinate: Coordinate(48.86, 2.35), lines: lines)
    }

    private func at(minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    @Test func groupsDeparturesByLineAndDestinationInTimeOrder() {
        let board = DepartureBoard(
            departures: [
                Departure(line: line1, destination: "La Défense", time: at(minutes: 6)),
                Departure(line: line1, destination: "Château de Vincennes", time: at(minutes: 1)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 2))
            ],
            stations: [station("Station", line1)],
            now: now
        )

        #expect(board.groups == [
            DepartureGroup(line: line1, destination: "Château de Vincennes", times: [at(minutes: 1)]),
            DepartureGroup(line: line1, destination: "La Défense", times: [at(minutes: 2), at(minutes: 6)])
        ])
    }

    @Test func ordersTheLinesOfEveryStationOfTheHubMetroFirstThenRER() {
        let line14 = TransitLine(mode: .metro, name: "14")
        let board = DepartureBoard(
            departures: [
                Departure(line: rerA, destination: "Boissy", time: at(minutes: 1)),
                Departure(line: line14, destination: "Olympiades", time: at(minutes: 2)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 5))
            ],
            stations: [station("Châtelet - Les Halles", rerA), station("Châtelet", line14, line1)],
            now: now
        )

        #expect(board.lines == [line1, line14, rerA])
        #expect(board.groups.map(\.line) == [line1, line14, rerA])
    }

    @Test func knowsWhichStationOfTheHubServesALine() {
        let board = DepartureBoard(
            departures: [],
            stations: [station("Châtelet - Les Halles", rerA), station("Châtelet", line1)],
            now: now
        )

        #expect(board.station(serving: line1)?.name == "Châtelet")
        #expect(board.station(serving: rerA)?.name == "Châtelet - Les Halles")
        #expect(board.station(serving: TransitLine(mode: .rer, name: "B")) == nil)
    }

    @Test func keepsOnlyTheNextThreeTimesOfAGroup() {
        let departures = (1...5).map {
            Departure(line: line1, destination: "La Défense", time: at(minutes: Double($0)))
        }

        let board = DepartureBoard(departures: departures, stations: [station("Station", line1)], now: now)

        #expect(board.groups.first?.times == [at(minutes: 1), at(minutes: 2), at(minutes: 3)])
    }

    @Test func dropsTrainsThatLeftMoreThanHalfAMinuteAgo() {
        let board = DepartureBoard(
            departures: [
                Departure(line: line1, destination: "La Défense", time: at(minutes: -1)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: -0.25))
            ],
            stations: [station("Station", line1)],
            now: now
        )

        #expect(board.groups.first?.times == [at(minutes: -0.25)])
    }

    @Test func dropsTimesMoreThanAnHourAwayAndKeepsTheCloserOnes() {
        let line13 = TransitLine(mode: .metro, name: "13")
        let board = DepartureBoard(
            departures: [
                Departure(line: line13, destination: "Châtillon Montrouge", time: at(minutes: 154)),
                Departure(line: line13, destination: "Châtillon Montrouge", time: at(minutes: 15)),
                Departure(line: line13, destination: "Châtillon Montrouge", time: at(minutes: 8)),
                Departure(line: line13, destination: "Les Courtilles", time: at(minutes: 8)),
                Departure(line: line13, destination: "Les Courtilles", time: at(minutes: 15)),
                Departure(line: line13, destination: "Les Courtilles", time: at(minutes: 25))
            ],
            stations: [station("Station", line13)],
            now: now
        )

        #expect(board.groups == [
            DepartureGroup(line: line13, destination: "Châtillon Montrouge", times: [at(minutes: 8), at(minutes: 15)]),
            DepartureGroup(
                line: line13,
                destination: "Les Courtilles",
                times: [at(minutes: 8), at(minutes: 15), at(minutes: 25)]
            )
        ])
        #expect(!board.departures.contains { $0.time == at(minutes: 154) })
    }

    @Test func keepsATimeExactlyAnHourAway() {
        let board = DepartureBoard(
            departures: [
                Departure(line: line1, destination: "La Défense", time: at(minutes: 60.01)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 60))
            ],
            stations: [station("Station", line1)],
            now: now
        )

        #expect(board.groups.first?.times == [at(minutes: 60)])
    }

    @Test func isEmptyWhenEveryTimeIsMoreThanAnHourAway() {
        let board = DepartureBoard(
            departures: [Departure(line: line1, destination: "La Défense", time: at(minutes: 61))],
            stations: [station("Station", line1)],
            now: now
        )

        #expect(board.isEmpty)
    }

    @Test func isEmptyWithoutUpcomingDepartures() {
        let board = DepartureBoard(
            departures: [Departure(line: line1, destination: "La Défense", time: at(minutes: -3))],
            stations: [station("Station", line1)],
            now: now
        )

        #expect(board.isEmpty)
    }

    @Test func hidesTimesThatHaveLeftSinceTheLastUpdate() {
        let group = DepartureGroup(line: line1, destination: "La Défense", times: [at(minutes: 1), at(minutes: 4)])

        #expect(group.upcomingTimes(after: at(minutes: 2)) == [at(minutes: 4)])
    }

    @Test(arguments: [
        (-0.5, 0),
        (0.0, 0),
        (0.9, 0),
        (1.0, 1),
        (4.99, 4),
        (12.0, 12)
    ])
    func countsWholeMinutesUntilATrain(minutesAway: Double, expected: Int) {
        #expect(DepartureTime.minutes(until: at(minutes: minutesAway), from: now) == expected)
    }
}
