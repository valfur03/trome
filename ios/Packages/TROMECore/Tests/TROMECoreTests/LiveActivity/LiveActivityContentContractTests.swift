import Foundation
import Testing
@testable import TROMECore

/// The content of the Live Activity that the server sends in a push must be the content that the app would draw
/// from the same PRIM answers: the widget decodes it into `ContentState` with no app to fix it.
/// Each case of `contracts/live-activity/cases/` names a station, a time and the answer of the server for each stop;
/// this test builds the content as the app does (the provider, the next trains model, the content state) and compares
/// it with `contracts/live-activity/contents/`, which the server's test compares with its own content.
/// `line-data.json` gives the server the rules of each line that live in this package (the PRIM line codes and the
/// ends of each line), so that one place holds them.
/// With `LIVE_ACTIVITY_CONTRACT_WRITE=1`, the test writes the contents and the line data instead of comparing.
@MainActor
struct LiveActivityContentContractTests {
    private nonisolated static let writes = ProcessInfo.processInfo.environment["LIVE_ACTIVITY_CONTRACT_WRITE"] == "1"

    struct Case: Decodable {
        struct Answer: Decodable {
            var prim: String?
            var answeredAt: String?
            var out: String?
            var retryAt: String?
        }

        var station: String
        var now: String
        var answers: [String: Answer]
    }

    nonisolated static func caseNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: Fixture.contractsFolder("live-activity/cases").path())
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    @Test(arguments: try caseNames())
    func theContentOfEachCaseIsTheContentOfTheApp(_ name: String) async throws {
        let folder = try Fixture.contractsFolder("live-activity")
        let contractCase = try JSONDecoder().decode(
            Case.self,
            from: Data(contentsOf: folder.appending(path: "cases/\(name).json"))
        )
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.station(withId: contractCase.station))
        let now = Fixture.date(contractCase.now)
        let client = ServerStubHTTPClient { request in try Self.reply(to: request, in: contractCase, now: now) }
        let model = NextTrainsModel(
            provider: PRIMDeparturesProvider(source: .server(.test), httpClient: client, now: { now }),
            catalog: catalog,
            now: { now }
        )
        await model.refresh(for: station)
        // A stop with no answer in the case would fail silently, as a stop that did not answer: each must be named.
        let asked = Set(client.requests.compactMap { $0.url?.absoluteString.removingPercentEncoding })
        #expect(asked.count == contractCase.answers.count, "\(name): the stops asked are not the stops of the case")
        for ref in contractCase.answers.keys {
            #expect(asked.contains { $0.contains("/\(ref)/") }, "\(name): \(ref) was not asked")
        }
        let content = StationActivityAttributes.ContentState(station: station, trains: model.state, now: now)
        let encoded = try JSONEncoder().encode(content)

        let contentFile = folder.appending(path: "contents/\(name).json")
        if Self.writes {
            try Self.write(encoded, to: contentFile)
            return
        }
        let recorded = try JSONSerialization.jsonObject(with: Data(contentsOf: contentFile)) as? NSDictionary
        let built = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
        #expect(recorded == built, "\(name): the recorded content is not the content of the app")
        // The widget decodes the push with a default decoder: the recorded file must decode the same way.
        let decoded = try JSONDecoder().decode(
            StationActivityAttributes.ContentState.self,
            from: Data(contentsOf: contentFile)
        )
        #expect(decoded == content)
    }

    @Test func theLineDataIsTheDataOfThePackage() throws {
        let catalog = try StationCatalog.bundled()
        var lines: [String: Any] = [:]
        for line in catalog.stations.flatMap(\.lines) {
            var entry: [String: Any] = [:]
            entry["primLineCode"] = line.primLineCode
            if let ends = line.ends {
                entry["ends"] = [
                    "first": ends.first,
                    "second": ends.second,
                    "branchStations": ends.branchStations,
                    "trunkStations": ends.trunkStations,
                    "otherNames": ends.otherNames
                ] as [String: Any]
            }
            lines["\(line.mode.rawValue)-\(line.name)"] = entry
        }
        let encoded = try JSONSerialization.data(withJSONObject: ["lines": lines], options: [.sortedKeys])
        let file = try Fixture.contractsFolder("live-activity").appending(path: "line-data.json")
        if Self.writes {
            try Self.write(encoded, to: file)
            return
        }
        let recorded = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? NSDictionary
        let built = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
        #expect(recorded == built, "line-data.json is not the line data of the package: write it again")
    }

    private nonisolated static func reply(
        to request: URLRequest,
        in contractCase: Case,
        now: Date
    ) throws -> ServerStubHTTPClient.Reply {
        let path = request.url?.absoluteString.removingPercentEncoding ?? ""
        guard let (_, answer) = contractCase.answers.first(where: { path.contains("/\($0.key)/") }) else {
            throw ContractError.noAnswer(path)
        }
        if let reason = answer.out {
            let retryAt = Fixture.date(answer.retryAt ?? "")
            let body = try JSONSerialization.data(withJSONObject: [
                "status": "out",
                "reason": reason,
                "retryAt": answer.retryAt ?? ""
            ])
            let retryAfter = Int(max(0, retryAt.timeIntervalSince(now)).rounded(.up))
            return .init(body: body, status: 503, headers: ["Retry-After": String(retryAfter)])
        }
        guard let prim = answer.prim, let answeredAt = answer.answeredAt else { throw ContractError.noAnswer(path) }
        return .init(
            body: try Fixture.data(prim),
            status: 200,
            headers: ["Content-Type": "application/json", "Last-Modified": httpDate(Fixture.date(answeredAt))]
        )
    }

    private nonisolated static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private static func write(_ data: Data, to file: URL) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        var pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        pretty.append(contentsOf: Array("\n".utf8))
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pretty.write(to: file)
    }

    enum ContractError: Error {
        case noAnswer(String)
    }
}
