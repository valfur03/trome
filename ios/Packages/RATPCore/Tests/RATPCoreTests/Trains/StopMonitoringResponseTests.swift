import Foundation
import Testing
@testable import RATPCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func date(_ text: String) -> Date {
        SIRIDate.parse(text) ?? .distantPast
    }
}

struct StopMonitoringResponseTests {
    @Test func readsEveryVisitThatHasALineATimeAndADestination() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-abbesses"))

        #expect(visits.count == 5)
        #expect(visits.first == MonitoredVisit(
            monitoringRef: "STIF:StopPoint:Q:463116:",
            lineRef: "STIF:Line::C01382:",
            destinationRef: "STIF:StopPoint:Q:463108:",
            destinationName: "Mairie d'Issy",
            journeyRef: "RATP-SIV:VehicleJourney::M12.R.1003:LOC",
            time: Fixture.date("2026-09-26T10:02:30Z"),
            arrivalTime: Fixture.date("2026-09-26T10:02:10Z"),
            status: "onTime",
            itemIdentifier: "RATP-SIV:Item::1.12.A.463116:LOC"
        ))
    }

    @Test func readsACancelledVisitAsCancelled() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-abbesses"))

        #expect(visits.map(\.isCancelled) == [false, false, false, false, true])
    }

    @Test func readsWhetherTheTrainIsAtTheStop() throws {
        let answer = try #require(String(bytes: Fixture.data("stop-monitoring-abbesses"), encoding: .utf8))
            .replacingOccurrences(of: "\"VehicleAtStop\": false", with: "\"VehicleAtStop\": true")

        let visits = try StopMonitoringResponse.visits(from: Data(answer.utf8))

        #expect(visits.map(\.isAtStop) == [true, true, false, false, false])
    }

    @Test func readsTheQuayAndTheDirectionOfEachTrainOfAStopArea() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-chatelet-rer"))

        #expect(visits.map(\.quayRef) == [
            "STIF:StopPoint:Q:473924:",
            "STIF:StopPoint:Q:473925:",
            "STIF:StopPoint:Q:473926:",
            "STIF:StopPoint:Q:473927:"
        ])
        #expect(visits.map(\.directionRef) == ["Aller", "Aller", "Retour", "Aller"])
    }

    @Test func readsNoQuayAndNoDirectionWhenTheAnswerHasNone() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-abbesses"))

        #expect(visits.allSatisfy { $0.quayRef == nil && $0.directionRef == nil })
    }

    @Test func readsTimesWithAndWithoutFractionalSeconds() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-abbesses"))

        #expect(visits[1].time == Fixture.date("2026-09-26T10:07:00.000Z"))
    }

    @Test func usesTheArrivalTimeWhenThereIsNoDepartureTime() throws {
        let visits = try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-abbesses"))

        #expect(visits[2].time == Fixture.date("2026-09-26T10:04:00Z"))
    }

    @Test func readsAnEmptyAnswer() throws {
        #expect(try StopMonitoringResponse.visits(from: Fixture.data("stop-monitoring-empty")).isEmpty)
    }

    @Test func readsAnAnswerWithoutDelivery() throws {
        let data = Data(#"{"Siri": {"ServiceDelivery": {"ResponseTimestamp": "2026-09-26T10:00:00Z"}}}"#.utf8)

        #expect(try StopMonitoringResponse.visits(from: data).isEmpty)
    }

    @Test func failsOnAnAnswerThatIsNotSIRI() {
        #expect(throws: (any Error).self) {
            try StopMonitoringResponse.visits(from: Data(#"{"error": "nope"}"#.utf8))
        }
    }
}
