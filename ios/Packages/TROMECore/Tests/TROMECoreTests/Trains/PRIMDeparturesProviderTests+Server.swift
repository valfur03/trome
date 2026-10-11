import Foundation
import Synchronization
import Testing
@testable import TROMECore

final class ServerStubHTTPClient: HTTPClient {
    struct Reply: Sendable {
        var body: Data
        var status: Int
        var headers: [String: String]
    }

    private let reply: @Sendable (URLRequest) throws -> Reply
    private let recorded = Mutex<[URLRequest]>([])

    init(reply: @escaping @Sendable (URLRequest) throws -> Reply) {
        self.reply = reply
    }

    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.withLock { $0.append(request) }
        let reply = try reply(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        return (reply.body, response)
    }
}

extension TrainServerConfiguration {
    static let test = TrainServerConfiguration(infoDictionary: [
        TrainServerConfiguration.hostKey: "trains.example.com",
        TrainServerConfiguration.appTokenKey: "test-app-token"
    ])!
}

extension PRIMDeparturesProviderTests {
    static let lastModified = "Sat, 26 Sep 2026 10:00:00 GMT"

    func serverProvider(
        _ reply: @escaping @Sendable (URLRequest) throws -> ServerStubHTTPClient.Reply
    ) -> (PRIMDeparturesProvider, ServerStubHTTPClient) {
        let client = ServerStubHTTPClient(reply: reply)
        return (PRIMDeparturesProvider(source: .server(.test), httpClient: client), client)
    }

    static func timesReply(
        _ fixture: String = "stop-monitoring-abbesses-stop-area",
        lastModified: String? = PRIMDeparturesProviderTests.lastModified
    ) throws -> ServerStubHTTPClient.Reply {
        var headers = ["Content-Type": "application/json"]
        headers["Last-Modified"] = lastModified
        return .init(body: try Fixture.data(fixture), status: 200, headers: headers)
    }

    @Test func sendsTheServerOnlyTheStopReferenceAndTheAppToken() async throws {
        let (provider, client) = serverProvider { _ in try Self.timesReply() }

        _ = try await provider.departures(at: [abbesses])

        let request = try #require(client.requests.first)
        #expect(client.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString == "https://trains.example.com/v1/stops/STIF:StopArea:SP:42155:/departures"
        )
        #expect(request.allHTTPHeaderFields == [
            "Authorization": "Bearer test-app-token",
            "Accept": "application/json"
        ])
        #expect(request.httpBody == nil)
        #expect(request.httpBodyStream == nil)
    }

    @Test func neverSendsThePRIMKeyOrAsksPRIMWhenItUsesTheServer() async throws {
        let (provider, client) = serverProvider { _ in try Self.timesReply() }

        _ = try await provider.departures(at: [abbessesByQuay])

        #expect(client.requests.count == 2)
        #expect(client.requests.allSatisfy { $0.url?.host() == "trains.example.com" })
        #expect(client.requests.allSatisfy { $0.value(forHTTPHeaderField: "apikey") == nil })
    }

    @Test func readsThePRIMAnswerThatTheServerGivesAsItIs() async throws {
        let (server, _) = serverProvider { _ in try Self.timesReply() }
        let (direct, _) = provider { _ in (try Fixture.data("stop-monitoring-abbesses-stop-area"), 200) }

        let answer = try await server.departuresAnswer(at: [abbesses])

        #expect(answer.departures == (try await direct.departures(at: [abbesses])))
        #expect(!answer.departures.isEmpty)
    }

    @Test func givesTheTimeWhenPRIMGaveTheAnswer() async throws {
        let (provider, _) = serverProvider { _ in try Self.timesReply() }

        let answer = try await provider.departuresAnswer(at: [abbesses])

        #expect(answer.answeredAt == Fixture.date("2026-09-26T10:00:00Z"))
    }

    @Test func givesNoAnswerTimeForADirectPRIMAnswer() async throws {
        let (provider, _) = provider { _ in (try Fixture.data("stop-monitoring-abbesses-stop-area"), 200) }

        let answer = try await provider.departuresAnswer(at: [abbesses])

        #expect(answer.answeredAt == nil)
    }

    @Test func givesTheTimeOfTheOldestAnswerWhenItAsksForSeveralStops() async throws {
        let (provider, _) = serverProvider { request in
            let olderStop = request.url?.absoluteString.contains("Q:22059:") == true
            return try Self.timesReply(lastModified: olderStop ? "Sat, 26 Sep 2026 09:58:00 GMT" : Self.lastModified)
        }

        let answer = try await provider.departuresAnswer(at: [abbessesByQuay])

        #expect(answer.answeredAt == Fixture.date("2026-09-26T09:58:00Z"))
    }

    @Test(arguments: [nil, "yesterday", "2026-09-26T10:00:00Z"] as [String?])
    func failsWhenTheServerDoesNotSayWhenPRIMGaveTheAnswer(lastModified: String?) async throws {
        let (provider, _) = serverProvider { _ in try Self.timesReply(lastModified: lastModified) }

        await #expect(throws: NextTrainsError.serviceFailure) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test(arguments: [
        (401, NextTrainsError.serviceFailure),
        (403, .serviceFailure),
        (400, .serviceFailure),
        (429, .serviceFailure),
        (500, .serviceFailure),
        (503, .serviceFailure)
    ])
    func turnsEachFailureOfTheServerIntoAFailedRefresh(status: Int, error: NextTrainsError) async {
        let (provider, _) = serverProvider { _ in .init(body: Data("{}".utf8), status: status, headers: [:]) }

        await #expect(throws: error) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test func saysTheServerRefusedTheAppTokenOnlyForItsOwnRefusal() async {
        let (provider, _) = serverProvider { _ in
            .init(body: Data(#"{"error":"unauthorized"}"#.utf8), status: 401, headers: [:])
        }

        await #expect(throws: NextTrainsError.appTokenRefused) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test func saysTheServerIsUnreachableWhenItDoesNotAnswer() async {
        let (provider, _) = serverProvider { _ in throw URLError(.timedOut) }

        await #expect(throws: NextTrainsError.unreachable) {
            try await provider.departures(at: [abbesses])
        }
    }
}
