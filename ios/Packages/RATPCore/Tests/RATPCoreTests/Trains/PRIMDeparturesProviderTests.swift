import Foundation
import Synchronization
import Testing
@testable import RATPCore

final class StubHTTPClient: HTTPClient {
    typealias Answer = @Sendable (URLRequest) throws -> (Data, Int)

    private let answer: Answer
    private let recorded = Mutex<[URLRequest]>([])

    init(answer: @escaping Answer) {
        self.answer = answer
    }

    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.withLock { $0.append(request) }
        let (data, statusCode) = try answer(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

struct PRIMDeparturesProviderTests {
    private let line12 = TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:22059", "IDFM:463116"])
    private var abbesses: Station {
        Station(id: "IDFM:22059", name: "Abbesses", coordinate: Coordinate(48.884388, 2.338381), lines: [line12])
    }
    private let chateletLesHalles = Station(
        id: "IDFM:monomodalStopPlace:45102",
        name: "Châtelet - Les Halles",
        coordinate: Coordinate(48.861745, 2.346977),
        lines: [
            TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:45102"]),
            TransitLine(mode: .rer, name: "B", stopIds: ["IDFM:monomodalStopPlace:45102"])
        ]
    )

    private func provider(_ answer: @escaping StubHTTPClient.Answer) -> (PRIMDeparturesProvider, StubHTTPClient) {
        let client = StubHTTPClient(answer: answer)
        return (PRIMDeparturesProvider(apiKey: "test-key", httpClient: client), client)
    }

    private func monitoringRef(of request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "MonitoringRef" }?.value
    }

    @Test func asksForEachStopOfTheStationWithTheKey() async throws {
        let (provider, client) = provider { _ in (try Fixture.data("stop-monitoring-empty"), 200) }

        _ = try await provider.departures(at: abbesses)

        #expect(Set(client.requests.compactMap(monitoringRef)) == [
            "STIF:StopPoint:Q:22059:",
            "STIF:StopPoint:Q:463116:"
        ])
        #expect(client.requests.allSatisfy { $0.value(forHTTPHeaderField: "apikey") == "test-key" })
        let endpoint = "https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring?"
        #expect(client.requests.allSatisfy { $0.url?.absoluteString.hasPrefix(endpoint) == true })
    }

    @Test func asksOnlyOnceForAStopSharedByTwoLines() async throws {
        let (provider, client) = provider { _ in (try Fixture.data("stop-monitoring-empty"), 200) }

        _ = try await provider.departures(at: chateletLesHalles)

        #expect(client.requests.compactMap(monitoringRef) == ["STIF:StopArea:SP:45102:"])
    }

    @Test func keepsTheStationTrainsOnceEachAndDropsTrainsThatEndHere() async throws {
        let (provider, _) = provider { _ in (try Fixture.data("stop-monitoring-abbesses"), 200) }

        let departures = try await provider.departures(at: abbesses)

        #expect(departures.map(\.destination) == ["Mairie d'Issy", "Mairie d'Issy"])
        #expect(departures.map(\.time) == [
            Fixture.date("2026-09-26T10:02:30Z"),
            Fixture.date("2026-09-26T10:07:00Z")
        ])
    }

    @Test func tellsTheMetroQuayEachTrainLeavesFrom() async throws {
        let (provider, _) = provider { request in
            if request.url?.absoluteString.contains("463116") == true {
                return (try Fixture.data("stop-monitoring-abbesses"), 200)
            }
            return (try Fixture.data("stop-monitoring-empty"), 200)
        }

        let departures = try await provider.departures(at: abbesses)

        #expect(departures == [
            Departure(
                line: line12,
                destination: "Mairie d'Issy",
                time: Fixture.date("2026-09-26T10:02:30Z"),
                quayRef: "STIF:StopPoint:Q:463116:"
            ),
            Departure(
                line: line12,
                destination: "Mairie d'Issy",
                time: Fixture.date("2026-09-26T10:07:00Z"),
                quayRef: "STIF:StopPoint:Q:463116:"
            )
        ])
    }

    @Test func tellsNoQuayForTheTrainsOfAStopArea() async throws {
        let (provider, _) = provider { _ in (try Fixture.data("stop-monitoring-abbesses"), 200) }
        let rerStation = Station(
            id: "rer",
            name: "Somewhere",
            coordinate: Coordinate(48.86, 2.34),
            lines: [TransitLine(mode: .metro, name: "12", stopIds: ["IDFM:monomodalStopPlace:45102"])]
        )

        let departures = try await provider.departures(at: rerStation)

        #expect(!departures.isEmpty)
        #expect(departures.allSatisfy { $0.quayRef == nil })
    }

    @Test func tellsTheQuayAndTheDirectionOfEachTrainOfAStopArea() async throws {
        let (provider, _) = provider { _ in (try Fixture.data("stop-monitoring-chatelet-rer"), 200) }

        let departures = try await provider.departures(at: chateletLesHalles)

        #expect(departures.map(\.line.name) == ["A", "A", "B", "B"])
        #expect(departures.map(\.quayRef) == [
            "STIF:StopPoint:Q:473924:",
            "STIF:StopPoint:Q:473925:",
            "STIF:StopPoint:Q:473926:",
            "STIF:StopPoint:Q:473927:"
        ])
        #expect(departures.map(\.directionRef) == ["Aller", "Aller", "Retour", "Aller"])
    }

    @Test func dropsTrainsWhoseDestinationIsTheStationItself() {
        let visit = MonitoredVisit(
            monitoringRef: "STIF:StopArea:SP:45102:",
            lineRef: "STIF:Line::C01742:",
            destinationRef: "STIF:StopPoint:Q:473921:",
            destinationName: "Chatelet-Les Halles",
            journeyRef: nil,
            time: Fixture.date("2026-09-26T10:02:00Z")
        )

        #expect(PRIMDeparturesProvider.departures(from: [visit], at: chateletLesHalles).isEmpty)
    }

    @Test func keepsTheLineOfEachTrainAtAStopSharedByTwoLines() {
        let visits = [("STIF:Line::C01742:", "Boissy-Saint-Léger"), ("STIF:Line::C01743:", "Robinson")].map {
            MonitoredVisit(
                monitoringRef: "STIF:StopArea:SP:45102:",
                lineRef: $0.0,
                destinationRef: nil,
                destinationName: $0.1,
                journeyRef: nil,
                time: Fixture.date("2026-09-26T10:02:00Z")
            )
        }

        let departures = PRIMDeparturesProvider.departures(from: visits, at: chateletLesHalles)

        #expect(departures.map(\.line.name) == ["A", "B"])
    }

    @Test func returnsNoDepartureWhenTheServiceHasNone() async throws {
        let (provider, _) = provider { _ in (try Fixture.data("stop-monitoring-empty"), 200) }

        #expect(try await provider.departures(at: abbesses).isEmpty)
    }

    @Test func keepsTheTrainsOfOneStopWhenAnotherStopFails() async throws {
        let (provider, _) = provider { request in
            if request.url?.absoluteString.contains("463116") == true {
                return (try Fixture.data("stop-monitoring-abbesses"), 200)
            }
            return (Data(), 500)
        }

        #expect(try await provider.departures(at: abbesses).count == 2)
    }

    @Test(arguments: [
        (401, NextTrainsError.keyRejected),
        (403, NextTrainsError.keyRejected),
        (429, NextTrainsError.quotaExceeded),
        (500, NextTrainsError.serviceFailure),
        (503, NextTrainsError.serviceFailure)
    ])
    func reportsAnHTTPError(statusCode: Int, expected: NextTrainsError) async {
        let (provider, _) = provider { _ in (Data(), statusCode) }

        await #expect(throws: expected) {
            try await provider.departures(at: abbesses)
        }
    }

    @Test func reportsAnUnreadableAnswerAsAServiceFailure() async {
        let (provider, _) = provider { _ in (Data("<html>oops</html>".utf8), 200) }

        await #expect(throws: NextTrainsError.serviceFailure) {
            try await provider.departures(at: abbesses)
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost])
    func reportsANetworkErrorAsUnreachable(code: URLError.Code) async {
        let (provider, _) = provider { _ in throw URLError(code) }

        await #expect(throws: NextTrainsError.unreachable) {
            try await provider.departures(at: abbesses)
        }
    }
}
