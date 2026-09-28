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

    @Test func namesTheStationOfTheHubThatServesALineOnlyWhenItIsNotTheFirstStation() {
        let board = DepartureBoard(
            departures: [
                Departure(line: rerA, destination: "Boissy", time: at(minutes: 1)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 5))
            ],
            stations: [station("Châtelet", line1), station("Châtelet - Les Halles", rerA)],
            now: now
        )

        #expect(board.otherStationName(serving: line1) == nil)
        #expect(board.otherStationName(serving: rerA) == "Châtelet - Les Halles")
        #expect(board.groups.map(\.stationName) == [nil, "Châtelet - Les Halles"])
    }

    @Test func namesTheStationOfTheHubForADestinationWhoseTimesAreAllMoreThanAnHourAway() {
        let board = DepartureBoard(
            departures: [Departure(line: rerA, destination: "Boissy", time: at(minutes: 70))],
            stations: [station("Châtelet", line1), station("Châtelet - Les Halles", rerA)],
            now: now
        )

        #expect(board.groups == [
            DepartureGroup(
                line: rerA,
                destination: "Boissy",
                times: [],
                stationName: "Châtelet - Les Halles",
                nextTrainIsOverAnHourAway: true
            )
        ])
    }

    @Test func namesNoStationForALineOfAnotherStationWithTheSameName() {
        let board = DepartureBoard(
            departures: [],
            stations: [
                Station(id: "metro", name: "Saint-Lazare", coordinate: Coordinate(48.87, 2.32), lines: [line1]),
                Station(id: "rer", name: "Saint-Lazare", coordinate: Coordinate(48.87, 2.32), lines: [rerA])
            ],
            now: now
        )

        #expect(board.otherStationName(serving: rerA) == nil)
    }

    @Test(arguments: [
        ("Opéra", [
            "3": nil, "7": nil, "8": nil, "9": "Havre-Caumartin", "12": "Saint-Lazare", "13": "Saint-Lazare",
            "14": "Saint-Lazare", "A": "Auber", "E": "Haussmann Saint-Lazare"
        ]),
        ("Châtelet", [
            "1": nil, "4": nil, "7": nil, "11": nil, "14": nil,
            "A": "Châtelet - Les Halles", "B": "Châtelet - Les Halles", "D": "Châtelet - Les Halles"
        ])
    ] as [(String, [String: String?])])
    func namesTheStationThatServesEachLineOfTheBundledHub(stationName: String, expected: [String: String?]) throws {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == stationName })

        let board = DepartureBoard(departures: [], stations: catalog.hubStations(of: station), now: now)

        #expect(Dictionary(uniqueKeysWithValues: board.lines.map { ($0.name, board.otherStationName(serving: $0)) })
            == expected)
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

    @Test func keepsADestinationWhoseEveryTimeIsMoreThanAnHourAwayAndSaysItsNextTrainIsOverAnHourAway() {
        let board = DepartureBoard(
            departures: [
                Departure(line: line1, destination: "La Défense", time: at(minutes: 70)),
                Departure(line: line1, destination: "La Défense", time: at(minutes: 61))
            ],
            stations: [station("Station", line1)],
            now: now
        )

        #expect(!board.isEmpty)
        #expect(board.groups == [
            DepartureGroup(line: line1, destination: "La Défense", times: [], nextTrainIsOverAnHourAway: true)
        ])
        #expect(board.departures.isEmpty)
        #expect(board.laterDepartures.map(\.time) == [at(minutes: 61), at(minutes: 70)])
    }

    @Test func showsEveryDestinationInOrderWhenOneHasOnlyTimesMoreThanAnHourAway() {
        let rerD = TransitLine(mode: .rer, name: "D")
        let board = DepartureBoard(
            departures: [
                Departure(line: rerD, destination: "Paris Gare de Lyon", time: at(minutes: 12)),
                Departure(line: rerD, destination: "Paris Gare de Lyon", time: at(minutes: 42)),
                Departure(line: rerD, destination: "Malesherbes", time: at(minutes: 65)),
                Departure(line: rerD, destination: "Paris Gare de Lyon", time: at(minutes: 72))
            ],
            stations: [station("Boigneville", rerD)],
            now: now
        )

        #expect(board.groups == [
            DepartureGroup(line: rerD, destination: "Malesherbes", times: [], nextTrainIsOverAnHourAway: true),
            DepartureGroup(line: rerD, destination: "Paris Gare de Lyon", times: [at(minutes: 12), at(minutes: 42)])
        ])
    }

    @Test func showsADestinationWithOnlyTimesMoreThanAnHourAwayAtAnyTime() {
        let later = DepartureGroup(line: line1, destination: "La Défense", times: [], nextTrainIsOverAnHourAway: true)
        let left = DepartureGroup(line: line1, destination: "Château de Vincennes", times: [at(minutes: 1)])

        #expect(later.isShown(at: at(minutes: 5)))
        #expect(left.isShown(at: now))
        #expect(!left.isShown(at: at(minutes: 2)))
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
