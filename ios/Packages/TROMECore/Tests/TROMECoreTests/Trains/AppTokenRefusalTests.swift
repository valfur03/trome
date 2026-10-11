import Foundation
import Testing
@testable import TROMECore

/// Only the refusal of the app token tells the rider to update the app: the recorded answers of the server
/// (an empty budget, a PRIM failure or limit, times, a bad stop), a time-out, no network, and other refusals
/// never do.
@MainActor
struct AppTokenRefusalTests {
    static let refusalExample = "departures-unauthorized"
    private let abbesses = PRIMDeparturesProviderTests().abbesses
    private let now = TrainServerContractTests.requestTime

    private func riderState(
        after reply: @escaping @Sendable (URLRequest) throws -> ServerStubHTTPClient.Reply
    ) async -> StationActivityAttributes.ContentState {
        let provider = PRIMDeparturesProvider(
            source: .server(.test),
            httpClient: ServerStubHTTPClient(reply: reply),
            now: { [now] in now }
        )
        let trains = NextTrainsModel(provider: provider, now: { [now] in now })
        await trains.refresh(for: abbesses)
        return StationActivityAttributes.ContentState(station: abbesses, trains: trains.state, now: now)
    }

    private func recordedReply(of name: String) throws -> ServerStubHTTPClient.Reply {
        let file = try JSONSerialization.jsonObject(with: Fixture.apiExample(name)) as? [String: Any]
        let response = try #require(file?["response"] as? [String: Any])
        let body: Data
        if let primAnswer = response["bodyIsPrimAnswer"] as? String {
            body = try Fixture.data(String(primAnswer.dropLast(".json".count)))
        } else {
            body = try JSONSerialization.data(withJSONObject: #require(response["body"]))
        }
        return .init(
            body: body,
            status: try #require(response["status"] as? Int),
            headers: response["headers"] as? [String: String] ?? [:]
        )
    }

    @Test func readsTheRecordedRefusal() {
        #expect(TrainServerContractTests.exampleNames.contains(Self.refusalExample))
    }

    @Test(arguments: TrainServerContractTests.exampleNames)
    func asksForAnUpdateOnlyForTheRefusalOfTheToken(name: String) async throws {
        let reply = try recordedReply(of: name)

        let state = await riderState { _ in reply }

        let isRefusal = name == Self.refusalExample
        #expect(state.appNeedsUpdate == isRefusal)
        #expect((state.dynamicIslandWait(isStale: false).wait == .updateTheApp) == isRefusal)
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost])
    func neverAsksForAnUpdateWhenTheServerDoesNotAnswer(code: URLError.Code) async {
        let state = await riderState { _ in throw URLError(code) }

        #expect(state.trains == .noData)
        #expect(!state.appNeedsUpdate)
    }

    @Test(arguments: [
        (401, #"{}"#),
        (401, "<html>Sign in to the network</html>"),
        (403, #"{"error":"unauthorized"}"#),
        (403, #"{"error":"forbidden"}"#)
    ])
    func neverAsksForAnUpdateForARefusalThatIsNotTheServers(status: Int, body: String) async {
        let state = await riderState { _ in .init(body: Data(body.utf8), status: status, headers: [:]) }

        #expect(state.trains == .noData)
        #expect(!state.appNeedsUpdate)
    }
}
