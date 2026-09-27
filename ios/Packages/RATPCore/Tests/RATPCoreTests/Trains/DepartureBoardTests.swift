import Foundation
import Testing
@testable import RATPCore

struct DepartureBoardTests {
    private let line1 = TransitLine(mode: .metro, name: "1")
    private let rerA = TransitLine(mode: .rer, name: "A")
    private let now = Date(timeIntervalSince1970: 1_000_000)

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
            lines: [line1],
            now: now
        )

        #expect(board.groups == [
            DepartureGroup(line: line1, destination: "Château de Vincennes", times: [at(minutes: 1)]),
            DepartureGroup(line: line1, destination: "La Défense", times: [at(minutes: 2), at(minutes: 6)])
        ])
    }

    @Test func ordersLinesAsTheStationListsThem() {
        let board = DepartureBoard(
            departures: [
                Departure(line: rerA, destination: "Boissy", time: at(minutes: 1)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 5))
            ],
            lines: [line1, rerA],
            now: now
        )

        #expect(board.groups.map(\.line) == [line1, rerA])
    }

    @Test func keepsOnlyTheNextThreeTimesOfAGroup() {
        let departures = (1...5).map {
            Departure(line: line1, destination: "La Défense", time: at(minutes: Double($0)))
        }

        let board = DepartureBoard(departures: departures, lines: [line1], now: now)

        #expect(board.groups.first?.times == [at(minutes: 1), at(minutes: 2), at(minutes: 3)])
    }

    @Test func dropsTrainsThatLeftMoreThanHalfAMinuteAgo() {
        let board = DepartureBoard(
            departures: [
                Departure(line: line1, destination: "La Défense", time: at(minutes: -1)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: -0.25))
            ],
            lines: [line1],
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
            lines: [line13],
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
            lines: [line1],
            now: now
        )

        #expect(board.groups.first?.times == [at(minutes: 60)])
    }

    @Test func isEmptyWhenEveryTimeIsMoreThanAnHourAway() {
        let board = DepartureBoard(
            departures: [Departure(line: line1, destination: "La Défense", time: at(minutes: 61))],
            lines: [line1],
            now: now
        )

        #expect(board.isEmpty)
    }

    @Test func isEmptyWithoutUpcomingDepartures() {
        let board = DepartureBoard(
            departures: [Departure(line: line1, destination: "La Défense", time: at(minutes: -3))],
            lines: [line1],
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
