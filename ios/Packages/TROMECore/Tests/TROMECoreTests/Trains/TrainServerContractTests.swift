import Foundation
import Testing
@testable import TROMECore

struct APIExample: Decodable {
    struct Request: Decodable {
        let method: String
        let path: String
        let headers: [String: String]
    }

    struct Response: Decodable {
        let status: Int
        let headers: [String: String]
        let bodyIsPrimAnswer: String?
    }

    let request: Request
    let response: Response
}

struct TrainServerContractTests {
    static let exampleNames = (try? Fixture.apiExampleNames()) ?? []
    private let abbesses = PRIMDeparturesProviderTests().abbesses

    private func example(_ name: String) throws -> APIExample {
        try JSONDecoder().decode(APIExample.self, from: Fixture.apiExample(name))
    }

    private func stopReference(in path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        try #require(parts.count == 4 && parts[0] == "v1" && parts[1] == "stops" && parts[3] == "departures")
        return try #require(String(parts[2]).removingPercentEncoding)
    }

    private func body(of example: APIExample) throws -> Data {
        guard let primAnswer = example.response.bodyIsPrimAnswer else { return Data("{}".utf8) }
        return try Fixture.data(String(primAnswer.dropLast(".json".count)))
    }

    @Test func readsEveryExampleOfTheAppAPI() {
        #expect(Self.exampleNames.count >= 7)
    }

    @Test(arguments: exampleNames)
    func asksForTheStopOfTheExampleAsTheServerExpects(name: String) throws {
        let example = try example(name)
        let provider = PRIMDeparturesProvider(source: .server(.test))

        let request = provider.request(for: try stopReference(in: example.request.path))

        #expect(request.httpMethod == example.request.method)
        #expect(request.url?.path(percentEncoded: false) == example.request.path)
        if let authorization = example.request.headers["authorization"] {
            let token = TrainServerConfiguration.test.appToken
            #expect(authorization.replacingOccurrences(of: "<APP_TOKEN>", with: token)
                == request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    @Test(arguments: exampleNames)
    func readsTheAnswerOfTheExample(name: String) async throws {
        let example = try example(name)
        let body = try body(of: example)
        let client = ServerStubHTTPClient { _ in
            .init(body: body, status: example.response.status, headers: example.response.headers)
        }
        let provider = PRIMDeparturesProvider(source: .server(.test), httpClient: client)

        switch example.response.status {
        case 200:
            let answer = try await provider.departuresAnswer(at: [abbesses])
            let lastModified = try #require(example.response.headers["last-modified"])
            #expect(answer.answeredAt == HTTPDate.parse(lastModified))
            #expect(answer.answeredAt != nil)
            #expect(answer.departures == (try await PRIMDeparturesProvider.departuresOfRecorded(body, at: abbesses)))
        case 401:
            await #expect(throws: NextTrainsError.keyRejected) { try await provider.departures(at: [abbesses]) }
        default:
            await #expect(throws: NextTrainsError.serviceFailure) { try await provider.departures(at: [abbesses]) }
        }
    }
}

private extension PRIMDeparturesProvider {
    static func departuresOfRecorded(_ body: Data, at station: Station) async throws -> [Departure] {
        let client = StubHTTPClient { _ in (body, 200) }
        return try await PRIMDeparturesProvider(apiKey: "test-key", httpClient: client).departures(at: [station])
    }
}
