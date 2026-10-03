import Foundation
import Testing
@testable import TROMECore

struct FakeTrainsScenarioTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func page(
        at name: String,
        _ scenario: FakeTrainsScenario,
        afterMinutes minutes: Double
    ) async throws -> LinesPage {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == name })
        let hub = catalog.hubStations(of: station)
        let now = start.addingTimeInterval(minutes * 60)
        let provider = FakeDeparturesProvider(scenario: scenario, start: start, now: { now })
        let board = DepartureBoard(departures: try await provider.departures(at: hub), stations: hub, now: now)
        let content = StationActivityAttributes.ContentState(
            station: station,
            trains: .departures(board, updatedAt: now),
            now: now
        )
        return try #require(content.trains.linesPage)
    }

    private func boxes(at name: String, _ scenario: FakeTrainsScenario, afterMinutes minutes: Double)
        async throws -> [[PlatformStatus?]] {
        try await page(at: name, scenario, afterMinutes: minutes).lines
            .flatMap(\.directions)
            .map { $0.trains.prefix(2).map(\.status) }
    }

    @Test(arguments: ["Lamarck - Caulaincourt", "Liège"])
    func putsTheFirstTrainOfEachStripAtThePlatformForFiveMinutes(station: String) async throws {
        for minutes in [0, 2.5, 4.9] {
            #expect(try await boxes(at: station, .atPlatform, afterMinutes: minutes) == [
                [.atPlatform, nil], [.atPlatform, nil]
            ])
        }
    }

    @Test func putsTheSecondTrainOfEachStripAtThePlatform() async throws {
        for minutes in [0, 3.4] {
            #expect(try await boxes(at: "Lamarck - Caulaincourt", .atPlatformSecond, afterMinutes: minutes) == [
                [nil, .atPlatform], [nil, .atPlatform]
            ])
        }
    }

    @Test func putsBothTrainsOfEachStripAtThePlatform() async throws {
        for minutes in [0, 2.5, 4.9] {
            #expect(try await boxes(at: "Lamarck - Caulaincourt", .atPlatformBoth, afterMinutes: minutes) == [
                [.atPlatform, .atPlatform], [.atPlatform, .atPlatform]
            ])
        }
    }

    @Test func putsTheTrainsOfAnRERLineAtThePlatformToo() async throws {
        let directions = try await page(at: "Sartrouville", .atPlatform, afterMinutes: 1).lines.flatMap(\.directions)

        #expect(!directions.isEmpty)
        #expect(directions.allSatisfy { $0.trains.first?.status == .atPlatform })
    }

    @Test(arguments: FakeTrainsScenario.allCases)
    func letsEachTrainLeaveLikeARealTrainAndNeverBringsItBack(scenario: FakeTrainsScenario) async throws {
        var shownTrains: [[Date]] = []
        var lastStatus: [Date: Int] = [:]
        for second in stride(from: 0.0, through: 20 * 60, by: 5) {
            let directions = try await page(at: "Liège", scenario, afterMinutes: second / 60).lines[0].directions
            shownTrains.append(directions.map { $0.trains[0].time })
            for train in directions.flatMap(\.trains) {
                let rank = [nil, .approaching, .atPlatform].firstIndex(of: train.status) ?? 0
                #expect(rank >= lastStatus[train.time, default: 0], "A train went back to an earlier state")
                lastStatus[train.time] = rank
            }
        }

        for (earlier, later) in zip(shownTrains, shownTrains.dropFirst()) {
            #expect(zip(earlier, later).allSatisfy { $0 <= $1 }, "A train that left came back in the first box")
        }
        #expect(Set(shownTrains.map { $0[0] }).count > 3)
    }

    @Test(arguments: ["Liège", "Poissonnière"])
    func countsTheSecondTrainOfTheForkDirectionFromTenToNineSoonAfterTheLaunchThenEverySixMinutes(
        station: String
    ) async throws {
        for drawnAfter in [0.0, 7.1] {
            let drawnAt = start.addingTimeInterval(drawnAfter * 60)
            let page = try await page(at: station, .tenToNine, afterMinutes: drawnAfter)
            let fork = try #require(page.lines[0].directions.first { $0.branchEnds != nil })
            let first = try #require(fork.trains.first)
            let second = try #require(fork.trains.dropFirst().first)
            let countsToNine = second.time.addingTimeInterval(-9 * 60 + 1)

            #expect(first.countdownMinutes(at: drawnAt) < 10)
            #expect(second.countdownMinutes(at: drawnAt) >= 10)
            #expect(second.countdownMinutes(at: countsToNine) == 9)
            #expect((60...5 * 60).contains(countsToNine.timeIntervalSince(drawnAt)))
            #expect(Set([first.destination, second.destination]) == Set(fork.branchEnds ?? []))
        }
    }

    @Test(arguments: [FakeTrainsScenario.atPlatform, .atPlatformSecond, .atPlatformBoth])
    func givesTheNextTwoTrainsOfTheForkDirectionOneForEachEnd(scenario: FakeTrainsScenario) async throws {
        let page = try await page(at: "Liège", scenario, afterMinutes: 1)
        let fork = try #require(page.lines[0].directions.first { $0.branchEnds != nil })

        #expect(Set(fork.trains.map(\.destination)) == Set(fork.branchEnds ?? []))
    }

    private func endRows(at name: String, _ scenario: FakeTrainsScenario, afterMinutes minutes: Double)
        async throws -> [BranchEndTrains] {
        let page = try await page(at: name, scenario, afterMinutes: minutes)
        let fork = try #require(page.lines[0].directions.first { $0.trainsOfEachEnd != nil })
        return try #require(fork.trainsOfEachEnd)
    }

    @Test(arguments: ["Liège", "Tolbiac"])
    func givesTheSecondEndOfTheForkOneTrainThenNone(station: String) async throws {
        let withOneTrain = try await endRows(at: station, .forkEndWithOneTrain, afterMinutes: 1)
        let afterItLeft = try await endRows(at: station, .forkEndWithOneTrain, afterMinutes: 9.5)

        #expect(withOneTrain.map(\.trains.count) == [2, 1])
        #expect(afterItLeft.map(\.trains.count) == [2, 0])
        #expect(!afterItLeft[1].nextTrainIsOverAnHourAway)
    }

    @Test(arguments: [(FakeTrainsScenario.forkEndWithNoTrain, false), (.forkEndOverAnHour, true)])
    func givesTheSecondEndOfTheForkNoTrainInTheHour(scenario: FakeTrainsScenario, isOverAnHour: Bool)
        async throws {
        for minutes in [0.0, 5, 9.5] {
            let rows = try await endRows(at: "Liège", scenario, afterMinutes: minutes)

            #expect(rows.map(\.trains.count) == [2, 0])
            #expect(rows[1].nextTrainIsOverAnHourAway == isOverAnHour)
        }
    }

    @Test(arguments: [FakeTrainsScenario.forkEndWithOneTrain, .forkEndWithNoTrain, .forkEndOverAnHour])
    func keepsTheTrainsOfAStationWithNoForkForEachEndState(scenario: FakeTrainsScenario) async throws {
        let directions = try await page(at: "Lamarck - Caulaincourt", scenario, afterMinutes: 1).lines[0].directions

        #expect(directions.map(\.trains.count) == [2, 2])
    }
}
