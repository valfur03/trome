import Foundation
import Testing
@testable import TROMECore

/// At a hub, the metro stop of Saint-Lazare (lines 3, 12, 13 and 14) did not answer while its other stops did.
extension StationActivityContentTests {
    static let saintLazareMetroStop = "STIF:StopArea:SP:462374:"
    static let saintLazareMetroLines: Set<String> = ["3", "12", "13", "14"]

    func saintLazarePages(
        withNoAnswerFrom unansweredStops: Set<String>,
        keeping keptLine: (String) -> Bool
    ) throws -> [LinesPage] {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == "Saint-Lazare" })
        let hub = catalog.hubStations(of: station)
        let departures = hub.flatMap { station in
            station.lines.flatMap { FakeDeparturesProvider.departures(of: $0, at: station, from: now, now: now) }
        }
        let board = DepartureBoard(
            departures: departures.filter { keptLine($0.line.name) },
            stations: hub,
            now: now,
            unansweredStops: unansweredStops
        )
        return try board.lines.indices.map { index in
            let content = StationActivityAttributes.ContentState(
                station: station,
                trains: .departures(board, updatedAt: now),
                now: now,
                firstLineIndex: index
            )
            return try #require(content.trains.linesPage)
        }
    }

    @Test func showsTheEndsOfTheLinesOfAStopThatDidNotAnswerWithEmptyBoxesAndTheTimesOfTheOthers() throws {
        let pages = try saintLazarePages(withNoAnswerFrom: [Self.saintLazareMetroStop]) { name in
            !Self.saintLazareMetroLines.contains(name)
        }
        let outLines = pages.flatMap(\.lines).filter { Self.saintLazareMetroLines.contains($0.line.name) }
        let otherLines = pages.flatMap(\.lines).filter { !Self.saintLazareMetroLines.contains($0.line.name) }
        let outDirections = outLines.flatMap(\.directions)
        let forkRows = outDirections.compactMap(\.branchEndRows).flatMap { $0 }

        #expect(outLines.count == 4)
        #expect(outLines.allSatisfy { !$0.hasNoTrain && $0.directions.count == 2 })
        #expect(outDirections.allSatisfy { $0.hasNoAnswer && $0.trains.isEmpty && !$0.label.isEmpty })
        #expect(!forkRows.isEmpty)
        #expect(forkRows.allSatisfy { $0.shown == .noAnswer })
        #expect(otherLines.flatMap(\.directions).allSatisfy { !$0.trains.isEmpty && !$0.hasNoAnswer })
        #expect(pages.allSatisfy { page in
            page.soonestTrain.map { !Self.saintLazareMetroLines.contains($0.line.name) } ?? false
        })
    }

    @Test func saysTheTimesOfALineAreUnavailableInTheIslandWhenNoOtherLineHasATrain() throws {
        let pages = try saintLazarePages(withNoAnswerFrom: [Self.saintLazareMetroStop]) { _ in false }
        let page = try #require(pages.first)
        let content = StationActivityAttributes.ContentState(
            stationName: "Saint-Lazare",
            trains: .lines(page),
            updatedAt: now
        )

        let island = content.dynamicIslandWait(isStale: false)

        #expect(island.line?.name == "3")
        #expect(island.wait == .noData)
        #expect(content.dynamicIslandWait(isStale: true).wait == .stale)
    }

    @Test func keepsSayingNoTrainForALineWhoseStopAnsweredWithNoTrain() throws {
        let pages = try saintLazarePages(withNoAnswerFrom: []) { name in
            !Self.saintLazareMetroLines.contains(name)
        }
        let line3 = try #require(pages.first?.lines.first)

        #expect(line3.line.name == "3")
        #expect(line3.directions.allSatisfy { $0.trains.isEmpty && !$0.hasNoAnswer })
    }
}
