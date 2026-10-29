import Foundation
import Testing
@testable import TROMECore

/// The examples of the start route in `contracts/api/`, which the server's own test answers in the same way:
/// the app asks as the server expects, and reads each answer into its case.
struct LiveActivityStartContractTests {
    static let exampleNames = (try? Fixture.apiExampleNames(of: "live-activity")) ?? []

    static let expectedAnswers: [String: LiveActivityStartAnswer] = [
        "live-activity-started": .started,
        "live-activity-already-started": .alreadyStarted,
        "live-activity-refused": .refused(reason: "BadDeviceToken"),
        "live-activity-refused-no-answer": .refused(reason: "no-answer"),
        "live-activity-not-set-up": .notSetUp
    ]

    private func example(_ name: String) throws -> (request: [String: Any], response: [String: Any]) {
        let file = try JSONSerialization.jsonObject(with: Fixture.apiExample(name)) as? [String: Any]
        return (try #require(file?["request"] as? [String: Any]), try #require(file?["response"] as? [String: Any]))
    }

    private func startToken(of request: [String: Any]) throws -> String {
        let body = try #require(request["body"] as? [String: Any])
        return try #require(body["startToken"] as? String)
    }

    private func stationId(in path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        try #require(parts.count == 4 && parts[0] == "v1" && parts[1] == "stations" && parts[3] == "live-activity")
        return String(parts[2])
    }

    @Test func readsAnExampleOfEachAnswerOfTheServer() {
        #expect(Set(Self.exampleNames) == Set(Self.expectedAnswers.keys))
    }

    @Test(arguments: exampleNames)
    func asksForTheStartAsTheServerExpects(name: String) throws {
        let request = try example(name).request
        let path = try #require(request["path"] as? String)
        let headers = try #require(request["headers"] as? [String: String])
        let starter = ServerLiveActivityStarter(server: .test, httpClient: ServerStubHTTPClient { _ in
            .init(body: Data(), status: 200, headers: [:])
        })

        let asked = starter.request(stationId: try stationId(in: path), startToken: try startToken(of: request))

        #expect(asked.httpMethod == request["method"] as? String)
        #expect(asked.url?.path(percentEncoded: false) == path)
        #expect(asked.url?.host() == "trains.example.com")
        for (header, value) in headers {
            let expected = value.replacingOccurrences(of: "<APP_TOKEN>", with: TrainServerConfiguration.test.appToken)
            #expect(asked.value(forHTTPHeaderField: header) == expected)
        }
        let body = try JSONSerialization.jsonObject(with: try #require(asked.httpBody)) as? [String: String]
        #expect(body == ["startToken": try startToken(of: request)])
    }

    @Test(arguments: exampleNames)
    func readsTheAnswerOfTheExampleIntoItsCase(name: String) async throws {
        let response = try example(name).response
        let body = try JSONSerialization.data(withJSONObject: #require(response["body"]))
        let status = try #require(response["status"] as? Int)
        let headers = response["headers"] as? [String: String] ?? [:]
        let starter = ServerLiveActivityStarter(server: .test, httpClient: ServerStubHTTPClient { _ in
            .init(body: body, status: status, headers: headers)
        })

        let answer = await starter.start(stationId: "IDFM:monomodalStopPlace:43234", startToken: "0123456789abcdef")

        #expect(answer == Self.expectedAnswers[name])
        #expect(answer.startsTheLiveActivity == (answer == .started || answer == .alreadyStarted))
    }

    @Test func onlyTheStartedAndAlreadyStartedAnswersStartTheLiveActivity() {
        let starting = Self.expectedAnswers.filter { $0.value.startsTheLiveActivity }.keys.sorted()

        #expect(starting == ["live-activity-already-started", "live-activity-started"])
        #expect(!LiveActivityStartAnswer.noAnswer.startsTheLiveActivity)
    }

    @Test(arguments: [
        (200, #"{"result":"queued"}"#),
        (200, "<html>Sign in to the network</html>"),
        (400, #"{"error":"bad request"}"#),
        (401, #"{"error":"unauthorized"}"#),
        (500, "Internal error"),
        (502, #"{"error":"bad gateway"}"#)
    ])
    func fallsBackFromAnAnswerThatItDoesNotKnow(status: Int, body: String) async {
        let starter = ServerLiveActivityStarter(server: .test, httpClient: ServerStubHTTPClient { _ in
            .init(body: Data(body.utf8), status: status, headers: [:])
        })

        let answer = await starter.start(stationId: "IDFM:monomodalStopPlace:43234", startToken: "0123456789abcdef")

        #expect(answer == .refused(reason: "HTTP \(status)"))
        #expect(!answer.startsTheLiveActivity)
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cannotFindHost, .cancelled])
    func saysNoAnswerWhenTheServerCannotBeReached(code: URLError.Code) async {
        let starter = ServerLiveActivityStarter(server: .test, httpClient: ServerStubHTTPClient { _ in
            throw URLError(code)
        })

        let answer = await starter.start(stationId: "IDFM:monomodalStopPlace:43234", startToken: "0123456789abcdef")

        #expect(answer == .noAnswer)
    }
}
