import Foundation
import TROMECore
import XCTest

extension LiveActivityRenderCheck {
    static let noAnswerStation = "Saint-Lazare"
    static let firstNoAnswerStatesPage = 130
    /// The metro stop area of Saint-Lazare (lines 3, 12, 13 and 14) and the stop of RER E at Haussmann.
    static let unansweredStops: Set<String> = ["STIF:StopArea:SP:462374:", "STIF:StopArea:SP:58718:"]
    static let unansweredLines: Set<String> = ["3", "12", "13", "14", "E"]
    /// The pages of line 3 (strips), line 13 (fork rows) and RER E (rows) at Saint-Lazare.
    static let noAnswerPageIndexes = [0, 2, 4]

    /// Two stops of the hub did not answer and the other three did: the lines of the stops that did not
    /// answer show their directions with empty boxes, and the island shows the next train of another line.
    static func noAnswerStates(at catalog: StationCatalog, hubDepartures: [Departure], now: Date) -> [StationState] {
        guard let station = catalog.stations.first(where: { $0.name == noAnswerStation }) else { return [] }
        let board = DepartureBoard(
            departures: hubDepartures.filter { !unansweredLines.contains($0.line.name) },
            stations: catalog.hubStations(of: station),
            now: now,
            unansweredStops: unansweredStops
        )
        return noAnswerPageIndexes.map { index in
            let state = StationActivityAttributes.ContentState(
                station: station,
                trains: .departures(board, updatedAt: now),
                now: now,
                firstLineIndex: index
            )
            return (station, state)
        }
    }

    /// Drawn with the states of a server that is out, since a stop that did not answer is often a stop that is out.
    func drawTheNoAnswerStates(
        of catalog: StationCatalog,
        fake: FakeDeparturesProvider,
        into outDir: URL
    ) async throws -> [String] {
        let now = Date()
        let station = try XCTUnwrap(catalog.stations.first { $0.name == Self.noAnswerStation })
        let hubDepartures = try await fake.departures(at: catalog.hubStations(of: station))
        let samples = Self.noAnswerStates(at: catalog, hubDepartures: hubDepartures, now: now)
        XCTAssertEqual(samples.count, 3, "States with a stop that did not answer that the render check could not build")
        var rows: [String] = []
        for (page, sample) in samples.enumerated() {
            let pageNumber = Self.firstNoAnswerStatesPage + page
            rows += try drawEveryVariant(of: sample.state, at: sample.station, page: pageNumber, into: outDir)
        }
        return rows
    }
}
