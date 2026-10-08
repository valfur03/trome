import Foundation
import Testing
@testable import TROMECore

/// One metro platform holds one train of a direction: a later train never reads "À quai" before an earlier one.
extension LineDirectionsTests {
    private var line6: TransitLine {
        TransitLine(mode: .metro, name: "6", stopIds: ["IDFM:10", "IDFM:11"])
    }

    private var line13: TransitLine {
        TransitLine(mode: .metro, name: "13", stopIds: ["IDFM:130", "IDFM:131"])
    }

    private func platformTrain(
        _ line: TransitLine,
        to destination: String,
        quay: String,
        leavesIn minutes: Double,
        arrivesIn arrival: Double? = nil,
        atStop: Bool = false
    ) -> Departure {
        Departure(
            line: line,
            destination: destination,
            time: time(inMinutes: minutes),
            quayRef: quay,
            arrivalTime: arrival.map { time(inMinutes: $0) },
            isAtStop: atStop
        )
    }

    private func toNation(leavesIn minutes: Double, arrivesIn arrival: Double? = nil, atStop: Bool = false)
        -> Departure {
        platformTrain(line6, to: "Nation", quay: "STIF:StopPoint:Q:11:", leavesIn: minutes, arrivesIn: arrival,
                      atStop: atStop)
    }

    private func nationStatuses(_ departures: [Departure]) throws -> [PlatformStatus?] {
        let nation = try #require(directions(of: line6, at: "Chevaleret", departures).first { $0.label == "Nation" })
        return nation.trains.map(\.status)
    }

    private func northOfLiege(_ departures: [Departure]) throws -> LineDirection {
        let result = LineDirections.directions(of: line13, at: station("Liège", [line13]), from: departures, now: now)
        return try #require(result.first { $0.branchEnds != nil })
    }

    private func toNorth(_ destination: String, leavesIn minutes: Double, arrivesIn arrival: Double? = nil,
                         atStop: Bool = false) -> Departure {
        platformTrain(line13, to: destination, quay: "STIF:StopPoint:Q:130:", leavesIn: minutes, arrivesIn: arrival,
                      atStop: atStop)
    }

    @Test func countsTheMinutesOfASecondTrainThatPRIMPutsAtThePlatformBeforeTheFirstTrainComes() throws {
        let saidAtTheStop = try nationStatuses([toNation(leavesIn: 4), toNation(leavesIn: 6, atStop: true)])
        let arrivedInThePast = try nationStatuses([toNation(leavesIn: 4), toNation(leavesIn: 5, arrivesIn: -1)])

        #expect(saidAtTheStop == [nil, nil])
        #expect(arrivedInThePast == [nil, nil])
    }

    @Test func countsTheMinutesOfASecondTrainAtThePlatformWhileTheFirstOneIsApproaching() throws {
        let statuses = try nationStatuses([toNation(leavesIn: 1, arrivesIn: 0.5), toNation(leavesIn: 5, atStop: true)])

        #expect(statuses == [.approaching, nil])
    }

    @Test func keepsTheFirstTrainAtThePlatformAndTheNextOneInMinutes() throws {
        let statuses = try nationStatuses([toNation(leavesIn: 0.5, atStop: true), toNation(leavesIn: 3)])

        #expect(statuses == [.atPlatform, nil])
    }

    @Test func showsTheNextTrainAtThePlatformOnceTheTrainBeforeItHasLeft() throws {
        let statuses = try nationStatuses([
            toNation(leavesIn: -0.2, arrivesIn: -0.7),
            toNation(leavesIn: 2, atStop: true)
        ])

        #expect(statuses == [.approaching, .atPlatform])
    }

    @Test func countsTheMinutesOfATrainOfOneEndWhenAnEarlierTrainOfTheOtherEndIsNotThereYet() throws {
        let direction = try northOfLiege([
            toNorth("Asnières-Gennevilliers Les Courtilles", leavesIn: 4),
            toNorth("Saint-Denis-Université", leavesIn: 5, atStop: true),
            toNorth("Saint-Denis-Université", leavesIn: 8, arrivesIn: -1)
        ])
        let saintDenis = try #require(direction.trainsOfEachEnd?.first { $0.end == "Saint-Denis - Université" })

        #expect(direction.trains.map(\.status) == [nil, nil])
        #expect(saintDenis.trains.map(\.status) == [nil, nil])
    }

    @Test func keepsTheTrainOfOneEndAtThePlatformWhenItIsTheFirstOfTheDirection() throws {
        let direction = try northOfLiege([
            toNorth("Saint-Denis-Université", leavesIn: 0.5, atStop: true),
            toNorth("Asnières-Gennevilliers Les Courtilles", leavesIn: 3)
        ])

        #expect(direction.trains.map(\.status) == [.atPlatform, nil])
        #expect(direction.trainsOfEachEnd?.map { $0.trains.map(\.status) } == [[.atPlatform], [nil]])
    }

    @Test func keepsWhatPRIMSaysOfASecondRERTrainAsAnRERPlatformCanHoldSeveralTrains() throws {
        let result = directions(of: rerB, at: "Châtelet - Les Halles", [
            train(rerB, to: "Mitry - Claye", inMinutes: 4, from: rerQuay(1)),
            train(rerB, to: "Mitry - Claye", inMinutes: 6, from: rerQuay(1), atStop: true)
        ])
        let north = try #require(result.first { $0.trains.contains { $0.destination == "Mitry - Claye" } })

        #expect(north.trains.map(\.status) == [nil, .atPlatform])
    }
}
