import Foundation
import Synchronization
import Testing
@testable import RATPCore

struct PRIMAnswerLogTests {
    private let base = PRIMDeparturesProviderTests()
    private let stopArea = "STIF:StopArea:SP:42155:"

    private func answer(_ visits: Result<[MonitoredVisit], any Error>) -> PRIMDeparturesProvider.Answer {
        PRIMDeparturesProvider.Answer(
            stopRequest: PRIMDeparturesProvider.StopRequest(monitoringRef: stopArea, lineCodes: ["C01382"]),
            visits: visits
        )
    }

    @Test func writesEachVisitOfAnAnswerWithWhatTheAppKeepsOrDrops() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-abbesses"))

        let lines = PRIMAnswerLog.lines(of: [answer(.success(visits))], at: [base.abbesses], timeZone: .gmt)

        let prefix = "PRIM \(stopArea) | "
        #expect(lines == [
            prefix + "5 visits",
            prefix + "kept | line STIF:Line::C01382: | to Mairie d'Issy | time 10:02:30 | arrival 10:02:10"
                + " | status onTime | quay STIF:StopPoint:Q:463116: | destination STIF:StopPoint:Q:463108:"
                + " | journey RATP-SIV:VehicleJourney::M12.R.1003:LOC | item RATP-SIV:Item::1.12.A.463116:LOC",
            prefix + "kept | line STIF:Line::C01382: | to Mairie d'Issy | time 10:07:00 | status onTime"
                + " | quay STIF:StopPoint:Q:463116: | destination STIF:StopPoint:Q:463108:"
                + " | journey RATP-SIV:VehicleJourney::M12.R.1007:LOC | item RATP-SIV:Item::1.12.A.463116.2:LOC",
            prefix + "dropped, ends here | line STIF:Line::C01382: | to Abbesses | time 10:04:00 | arrival 10:04:00"
                + " | quay STIF:StopPoint:Q:463116: | destination STIF:StopPoint:Q:463116:"
                + " | journey RATP-SIV:VehicleJourney::M12.R.1009:LOC | item RATP-SIV:Item::1.12.A.463116.3:LOC",
            prefix + "dropped, line not asked | line STIF:Line::C01100: | to Gare du Nord | time 10:03:00"
                + " | item RATP-SIV:Item::bus.40:LOC",
            prefix + "dropped, cancelled | line STIF:Line::C01382: | to Mairie d'Issy | time 10:05:00"
                + " | status cancelled | quay STIF:StopPoint:Q:463116: | destination STIF:StopPoint:Q:463108:"
                + " | journey RATP-SIV:VehicleJourney::M12.R.1011:LOC | item RATP-SIV:Item::1.12.A.463116.5:LOC"
        ])
    }

    @Test func writesAVisitOfAJourneyThatAnEarlierVisitAlreadyGave() {
        let visit = MonitoredVisit(
            lineRef: "STIF:Line::C01382:",
            destinationName: "Mairie d'Issy",
            journeyRef: "M12.R.1",
            time: Fixture.date("2026-09-26T10:02:00Z"),
            isAtStop: true,
            aimedTime: Fixture.date("2026-09-26T10:01:00Z")
        )

        let lines = PRIMAnswerLog.lines(of: [answer(.success([visit, visit]))], at: [base.abbesses], timeZone: .gmt)

        #expect(lines.dropFirst() == [
            "PRIM \(stopArea) | kept | line STIF:Line::C01382: | to Mairie d'Issy | time 10:02:00"
                + " | aimed 10:01:00 | at stop yes | journey M12.R.1",
            "PRIM \(stopArea) | dropped, same journey as an earlier visit | line STIF:Line::C01382:"
                + " | to Mairie d'Issy | time 10:02:00 | aimed 10:01:00 | at stop yes | journey M12.R.1"
        ])
    }

    @Test func writesAFailedCall() {
        let lines = PRIMAnswerLog.lines(of: [answer(.failure(NextTrainsError.quotaExceeded))], at: [base.abbesses])

        #expect(lines == ["PRIM \(stopArea) | failed: quotaExceeded"])
    }

    @Test func givesEachLineToTheLogAndKeepsTheSameTrains() async throws {
        let client = StubHTTPClient { _ in (try Fixture.data("stop-monitoring-abbesses"), 200) }
        let lines = Mutex<[String]>([])
        let logging = PRIMDeparturesProvider(apiKey: "test-key", httpClient: client) { line in
            lines.withLock { $0.append(line) }
        }
        let silent = PRIMDeparturesProvider(apiKey: "test-key", httpClient: client)

        let logged = try await logging.departures(at: [base.abbesses])
        let notLogged = try await silent.departures(at: [base.abbesses])

        #expect(logged == notLogged)
        #expect(lines.withLock { $0.count } == 6)
    }
}
