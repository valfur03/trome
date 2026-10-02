import Foundation
import Testing
@testable import RATPCore

extension BranchEndRowTests {
    private static let saintDenis = "Saint-Denis - Université"
    private static let asnieres = "Asnières - Gennevilliers - Les Courtilles"

    private func liegeLine13(recordedIn fixture: String, at answeredAt: String) throws -> LineTrains {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == "Liège" })
        let now = Fixture.date(answeredAt)
        let visits = try StopMonitoringResponse.visits(from: Fixture.data(fixture))
        let board = DepartureBoard(
            departures: PRIMDeparturesProvider.departures(from: visits, at: [station]),
            stations: [station],
            now: now
        )
        let content = StationActivityAttributes.ContentState(
            station: station,
            trains: .departures(board, updatedAt: now),
            now: now
        )
        return try #require(content.trains.linesPage?.panamStripsLine)
    }

    private func north(of line: LineTrains) throws -> [BranchEndRow] {
        try #require(line.directions.compactMap(\.branchEndRows).first)
    }

    private func times(_ shown: BranchEndRow.Shown) -> [Date] {
        guard case .trains(let trains) = shown else { return [] }
        return trains.map(\.time)
    }

    @Test func showsTheAsnieresTrainAtThePlatformFirstInTheAnswerOf170043() throws {
        let rows = try north(of: liegeLine13(
            recordedIn: "stop-monitoring-liege-170043",
            at: "2026-10-02T15:00:43.197Z"
        ))

        #expect(rows.map(\.end) == [Self.saintDenis, Self.asnieres])
        #expect(times(rows[0].shown) == [Fixture.date("2026-10-02T15:03:12Z")])
        #expect(times(rows[1].shown) == [Fixture.date("2026-10-02T15:01:04Z"), Fixture.date("2026-10-02T15:04:46Z")])
        guard case .trains(let asnieres) = rows[1].shown else { return }
        #expect(asnieres.first?.status == .atPlatform)
    }

    @Test func showsADashNotTheNoTrainWordsForAsnieresInTheAnswerOf170558() throws {
        let line = try liegeLine13(recordedIn: "stop-monitoring-liege-170558", at: "2026-10-02T15:05:58.920Z")
        let rows = try north(of: line)

        #expect(rows.map(\.end) == [Self.saintDenis, Self.asnieres])
        #expect(times(rows[0].shown) == [Fixture.date("2026-10-02T15:08:49Z"), Fixture.date("2026-10-02T15:11:04Z")])
        #expect(rows[1].shown == .notListed)
        #expect(line.directions.first { $0.branchEndRows == nil }?.trains.count == 2)
    }

    @Test func givesEachEndItsOwnTrainsInTheAnswerOf171032() throws {
        let rows = try north(of: liegeLine13(
            recordedIn: "stop-monitoring-liege-171032",
            at: "2026-10-02T15:10:32.737Z"
        ))

        #expect(times(rows[0].shown) == [Fixture.date("2026-10-02T15:16:02Z")])
        #expect(times(rows[1].shown) == [Fixture.date("2026-10-02T15:14:02Z"), Fixture.date("2026-10-02T15:18:02Z")])
    }

    @Test(arguments: [
        ("stop-monitoring-liege-170043", 4), ("stop-monitoring-liege-170558", 3), ("stop-monitoring-liege-171032", 3)
    ])
    func readsThreeOrFourTrainsOfTheForkDirectionInEachRecordedAnswer(fixture: String, count: Int) throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data(fixture))

        #expect(visits.filter { $0.directionRef == "Aller" }.count == count)
    }
}
