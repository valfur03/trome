import Foundation
import Testing
@testable import TROMECore

extension PRIMDeparturesProviderTests {
    static func outReply(
        reason: String = "budget",
        retryAt: String = "2026-10-02T09:00:40.000Z",
        retryAfter: String? = "1840"
    ) -> ServerStubHTTPClient.Reply {
        var headers = ["Content-Type": "application/json"]
        headers["Retry-After"] = retryAfter
        let body = #"{"status":"out","reason":"\#(reason)","retryAt":"\#(retryAt)"}"#
        return .init(body: Data(body.utf8), status: 503, headers: headers)
    }

    func serverProvider(
        clock: TestClock,
        _ reply: @escaping @Sendable (URLRequest) throws -> ServerStubHTTPClient.Reply
    ) -> (PRIMDeparturesProvider, ServerStubHTTPClient) {
        let client = ServerStubHTTPClient(reply: reply)
        let provider = PRIMDeparturesProvider(source: .server(.test), httpClient: client, now: { clock.now })
        return (provider, client)
    }

    @Test(arguments: ["budget", "prim-limit"])
    func saysTheServerIsOutUntilTheTimeItGives(reason: String) async {
        let clock = TestClock()
        let (provider, _) = serverProvider(clock: clock) { _ in Self.outReply(reason: reason) }

        await #expect(throws: NextTrainsError.serverOut(retryAt: clock.now.addingTimeInterval(1_840))) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test func keepsTheUsualFailureWhenPRIMItselfFailed() async {
        let clock = TestClock()
        let (provider, _) = serverProvider(clock: clock) { _ in
            Self.outReply(reason: "prim-failure", retryAfter: "60")
        }

        await #expect(throws: NextTrainsError.serviceFailure) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test(arguments: [("budget", 1_840.0), ("prim-failure", 60)])
    func asksTheServerNothingForTheStopBeforeTheRetryTime(reason: String, retryAfter: TimeInterval) async {
        let clock = TestClock()
        let (provider, client) = serverProvider(clock: clock) { _ in
            Self.outReply(reason: reason, retryAfter: "\(Int(retryAfter))")
        }
        _ = try? await provider.departures(at: [abbesses])

        clock.advance(by: retryAfter - 1)
        let error = await #expect(throws: NextTrainsError.self) { try await provider.departures(at: [abbesses]) }

        #expect(client.requests.count == 1)
        #expect(error == (reason == "budget" ? .serverOut(retryAt: clock.now.addingTimeInterval(1)) : .serviceFailure))
    }

    @Test func asksAgainOnceAtTheRetryTimeAndTakesTheNewRetryTimeWhenTheServerIsStillOut() async {
        let clock = TestClock()
        let (provider, client) = serverProvider(clock: clock) { _ in Self.outReply() }
        _ = try? await provider.departures(at: [abbesses])

        clock.advance(by: 1_840)
        let secondRetryAt = clock.now.addingTimeInterval(1_840)
        await #expect(throws: NextTrainsError.serverOut(retryAt: secondRetryAt)) {
            try await provider.departures(at: [abbesses])
        }
        clock.advance(by: 30)
        _ = try? await provider.departures(at: [abbesses])

        #expect(client.requests.count == 2)
    }

    @Test func givesTheTimesAtOnceWhenTheyComeBackAtTheRetryTime() async throws {
        let clock = TestClock()
        let retryAt = clock.now.addingTimeInterval(1_840)
        let (provider, client) = serverProvider(clock: clock) { _ in
            clock.now < retryAt ? Self.outReply() : try Self.timesReply()
        }
        _ = try? await provider.departures(at: [abbesses])

        clock.advance(by: 1_840)
        let departures = try await provider.departures(at: [abbesses])
        _ = try await provider.departures(at: [abbesses])

        #expect(!departures.isEmpty)
        #expect(client.requests.count == 3)
    }

    @Test func waitsTheDelayOfTheServerEvenWhenThePhoneClockIsWrong() async {
        let clock = TestClock()
        let (provider, _) = serverProvider(clock: clock) { _ in
            Self.outReply(retryAt: "1970-01-01T00:00:00.000Z", retryAfter: "1840")
        }

        await #expect(throws: NextTrainsError.serverOut(retryAt: clock.now.addingTimeInterval(1_840))) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test func takesTheRetryTimeOfTheAnswerWhenTheServerGivesNoDelay() async {
        let clock = TestClock()
        let retryAt = clock.now.addingTimeInterval(1_840)
        let (provider, _) = serverProvider(clock: clock) { _ in
            Self.outReply(retryAt: retryAt.formatted(.iso8601), retryAfter: nil)
        }

        await #expect(throws: NextTrainsError.serverOut(retryAt: retryAt)) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test(arguments: ["0", "-5"])
    func waitsAtLeastHalfAMinuteBeforeItAsksAgain(retryAfter: String) async {
        let clock = TestClock()
        let (provider, _) = serverProvider(clock: clock) { _ in Self.outReply(retryAfter: retryAfter) }

        await #expect(throws: NextTrainsError.serverOut(retryAt: clock.now.addingTimeInterval(30))) {
            try await provider.departures(at: [abbesses])
        }
    }

    @Test func givesTheLatestRetryTimeWhenEveryStopOfTheStationIsOut() async {
        let clock = TestClock()
        let (provider, _) = serverProvider(clock: clock) { request in
            let later = request.url?.absoluteString.contains("Q:22059:") == true
            return Self.outReply(retryAfter: later ? "1880" : "1840")
        }

        await #expect(throws: NextTrainsError.serverOut(retryAt: clock.now.addingTimeInterval(1_880))) {
            try await provider.departures(at: [abbessesByQuay])
        }
    }

    @Test func asksEveryStopOfTheStationAgainAtTheRetryTimeItGives() async throws {
        let clock = TestClock()
        let firstAnswerAt = clock.now
        let (provider, client) = serverProvider(clock: clock) { request in
            let later = request.url?.absoluteString.contains("Q:22059:") == true
            guard clock.now == firstAnswerAt else { return try Self.timesReply() }
            return Self.outReply(retryAfter: later ? "1880" : "1840")
        }
        let firstError = await #expect(throws: NextTrainsError.self) {
            try await provider.departures(at: [abbessesByQuay])
        }

        clock.advance(by: try #require(firstError?.serverRetryAt).timeIntervalSince(clock.now))
        let departures = try await provider.departures(at: [abbessesByQuay])

        #expect(!departures.isEmpty)
        #expect(client.requests.count == 4)
    }

    @Test func keepsAskingForTheOtherStopsWhileOneStopIsOut() async throws {
        let clock = TestClock()
        let (provider, client) = serverProvider(clock: clock) { request in
            request.url?.absoluteString.contains("Q:22059:") == true ? Self.outReply() : try Self.timesReply()
        }
        _ = try await provider.departures(at: [abbessesByQuay])

        clock.advance(by: 30)
        let departures = try await provider.departures(at: [abbessesByQuay])

        #expect(!departures.isEmpty)
        #expect(client.requests.count == 3)
        #expect(client.requests.last?.url?.absoluteString.contains("Q:22059:") == false)
    }

    @Test func neverWaitsForARetryTimeWhenItAsksPRIMDirectly() async {
        let (provider, client) = provider { _ in
            (Data(#"{"status":"out","reason":"budget","retryAt":"2099-01-01T00:00:00Z"}"#.utf8), 503)
        }

        await #expect(throws: NextTrainsError.serviceFailure) { try await provider.departures(at: [abbesses]) }
        await #expect(throws: NextTrainsError.serviceFailure) { try await provider.departures(at: [abbesses]) }

        #expect(client.requests.count == 2)
    }
}
