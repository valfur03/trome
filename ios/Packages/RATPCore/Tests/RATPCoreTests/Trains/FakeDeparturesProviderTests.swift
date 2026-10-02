import Foundation
import Testing
@testable import RATPCore

struct FakeDeparturesProviderTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let line4 = TransitLine(mode: .metro, name: "4")
    let line5 = TransitLine(mode: .metro, name: "5")
    let line7 = TransitLine(mode: .metro, name: "7")
    let line8 = TransitLine(mode: .metro, name: "8")
    let line12 = TransitLine(mode: .metro, name: "12")

    func station(_ name: String, _ lines: [TransitLine]) -> Station {
        Station(id: name, name: name, coordinate: Coordinate(48.85, 2.35), lines: lines)
    }

    func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    func departures(at stations: [Station]) async throws -> [Departure] {
        let now = now
        return try await FakeDeparturesProvider(now: { now }).departures(at: stations)
    }

    @Test func givesTrainsTowardBothEndsWithTimesFromNow() async throws {
        let result = try await departures(at: [station("Abbesses", [line12])])

        #expect(result == [
            Departure(line: line12, destination: "Mairie d'Aubervilliers", time: time(inMinutes: 3)),
            Departure(line: line12, destination: "Mairie d'Aubervilliers", time: time(inMinutes: 7)),
            Departure(line: line12, destination: "Mairie d'Aubervilliers", time: time(inMinutes: 11)),
            Departure(line: line12, destination: "Mairie d'Aubervilliers", time: time(inMinutes: 15)),
            Departure(line: line12, destination: "Mairie d'Issy", time: time(inMinutes: 4)),
            Departure(line: line12, destination: "Mairie d'Issy", time: time(inMinutes: 8)),
            Departure(line: line12, destination: "Mairie d'Issy", time: time(inMinutes: 12)),
            Departure(line: line12, destination: "Mairie d'Issy", time: time(inMinutes: 16))
        ])
    }

    @Test func sendsTheTrainsOfABranchedSideToEachBranchInTurn() async throws {
        let result = try await departures(at: [station("Poissonnière", [line7])])

        #expect(result.filter { $0.destination != "La Courneuve - 8 Mai 1945" }.map(\.destination) == [
            "Mairie d'Ivry", "Villejuif - Louis Aragon", "Mairie d'Ivry", "Villejuif - Louis Aragon"
        ])
    }

    @Test func sendsTheTrainsOnABranchOnlyToTheEndOfThatBranch() async throws {
        let result = try await departures(at: [station("Porte d'Italie", [line7])])

        #expect(Set(result.map(\.destination)) == ["La Courneuve - 8 Mai 1945", "Mairie d'Ivry"])
    }

    @Test func givesNoTrainTowardTheStationAtTheEndOfTheLine() async throws {
        let result = try await departures(at: [station("Balard", [line8])])

        #expect(Set(result.map(\.destination)) == ["Pointe du Lac"])
    }

    @Test func givesTrainsForEachLineOfEachStationOfAHub() async throws {
        let hub = [station("Gare de l'Est", [line4, line5]), station("Château Landon", [line7])]
        let result = try await departures(at: hub)

        #expect(Set(result.map(\.line)) == [line4, line5, line7])
    }

    @Test func showsEachBranchOfALineOnTheNextLinesOfAHub() async throws {
        let hub = [station("Gare de l'Est", [line4, line5, line7])]
        let board = DepartureBoard(departures: try await departures(at: hub), stations: hub, now: now)

        let content = StationActivityAttributes.ContentState(
            station: hub[0],
            trains: .departures(board, updatedAt: now),
            now: now,
            firstLineIndex: 2
        )

        #expect(content.trains.linesPage?.lines == [
            LineTrains(line: line7, directions: [
                LineDirection(label: "La Courneuve - 8 Mai 1945", times: [time(inMinutes: 3), time(inMinutes: 7)]),
                LineDirection(label: "Mairie d'Ivry / Villejuif - Louis Aragon", trains: [
                    LineDirection.Train(time: time(inMinutes: 4), destination: "Mairie d'Ivry"),
                    LineDirection.Train(time: time(inMinutes: 8), destination: "Villejuif - Louis Aragon")
                ], branchEnds: ["Mairie d'Ivry", "Villejuif - Louis Aragon"], trainsOfEachEnd: [
                    BranchEndTrains(end: "Mairie d'Ivry", trains: [
                        LineDirection.Train(time: time(inMinutes: 4), destination: "Mairie d'Ivry"),
                        LineDirection.Train(time: time(inMinutes: 12), destination: "Mairie d'Ivry")
                    ]),
                    BranchEndTrains(end: "Villejuif - Louis Aragon", trains: [
                        LineDirection.Train(time: time(inMinutes: 8), destination: "Villejuif - Louis Aragon"),
                        LineDirection.Train(time: time(inMinutes: 16), destination: "Villejuif - Louis Aragon")
                    ])
                ])
            ], hasADirectionWithTwoEnds: true)
        ])
    }

    @Test func isGivenOnlyWhenTheLaunchArgumentAsksForIt() {
        #expect(FakeDeparturesProvider.ifAsked(by: ["RATPActivity", FakeDeparturesProvider.launchArgument]) != nil)
        #expect(FakeDeparturesProvider.ifAsked(by: ["RATPActivity"]) == nil)
    }
}
