import Foundation
import Testing
@testable import TROMECore

/// The start of the Live Activity in the newest recorded set of promises of `contracts/builds/` is true of the app
/// code: the app sends the request of the set, asks only for stations of the shapes that it names, waits as long as
/// it says, and reads each promised answer as the set says.
/// Why: the set of a new build is copied from the newest one at its upload, and the server is judged against it
/// (`make server-check`); a set that the app code does not keep lets the server check pass while the start breaks.
struct LiveActivityStartPromisesTests {
    /// The first build that asks the server to start the Live Activity: every set from it holds the start.
    static let firstBuildThatStarts = BuildNumber(version: [1, 0, 0], build: 4)

    private struct Newest {
        let set: BuildPromiseSet
        let start: LiveActivityStartPromise
    }

    /// The start of the newest set, or nil when its builds are older than the first build that starts.
    private func newest() throws -> Newest? {
        let set = try BuildPromisesTests.newest.get()
        guard let start = set.liveActivityStart else {
            #expect(
                BuildNumber.newest(of: set.builds) < Self.firstBuildThatStarts,
                "\(set.name) has a build that starts the Live Activity, but no liveActivityStart"
            )
            return nil
        }
        return Newest(set: set, start: start)
    }

    @Test func readsTheStartOfTheNewestSet() throws {
        guard let newest = try newest() else { return }
        let start = newest.start
        #expect(!start.stations.isEmpty && !start.startTokens.isEmpty && !start.answers.isEmpty, "\(newest.set.name)")
        let names = start.answers.map(\.when)
        #expect(Set(names).count == names.count, "two start answers of \(newest.set.name) have one \"when\"")
    }

    @Test func sendsTheRequestOfTheSetForEveryStationAndStartToken() async throws {
        guard let newest = try newest() else { return }
        let start = newest.start
        let headers = Dictionary(uniqueKeysWithValues: start.request.headers.map { name, value in
            (name.lowercased(), newest.set.requestHeader(value))
        })
        for station in start.stations {
            for token in start.startTokens {
                let client = ServerStubHTTPClient { _ in .init(body: Data(), status: 503, headers: [:]) }
                let starter = ServerLiveActivityStarter(server: .test, httpClient: client)
                _ = await starter.start(stationId: station.station, startToken: token.startToken)
                let request = try #require(client.requests.first)
                let url = try #require(request.url)
                let sent = Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { name, value in
                    (name.lowercased(), value)
                })
                let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))

                #expect(request.httpMethod == start.request.method, "\(station.station)")
                #expect(url.scheme == "https" && url.host() == "trains.example.com" && url.query() == nil, "\(url)")
                let path = start.request.path.replacingOccurrences(of: "<STATION>", with: station.station)
                #expect(url.path(percentEncoded: true) == path)
                #expect(sent == headers, "\(station.station)")
                #expect(body == start.request.body.mapValues {
                    $0.replacingOccurrences(of: "<START_TOKEN>", with: token.startToken)
                })
                #expect(request.timeoutInterval == start.app.waitForTheAnswerSeconds, "\(station.station)")
            }
        }
    }

    @Test func givesUpOnTheAnswerAfterTheWaitOfTheSet() throws {
        guard let newest = try newest() else { return }

        #expect(SilentStart.answerLimit == .seconds(newest.start.app.waitForTheAnswerSeconds))
    }

    @Test func startsOnlyStationsOfAShapeThatTheSetPromises() throws {
        guard let newest = try newest() else { return }
        let asked = Set(try StationCatalog.bundled().stations.map { Self.shape(of: $0.id) })
        let promised = Set(newest.start.stations.map { Self.shape(of: $0.station) })

        #expect(!asked.isEmpty)
        #expect(asked.subtracting(promised).isEmpty, "\(newest.set.name) promises only the shapes \(promised.sorted())")
    }

    @Test func readsEachAnswerAsTheSetSays() async throws {
        guard let newest = try newest() else { return }
        let start = newest.start
        var problems: [String] = []
        var count = 0
        for answer in start.answers {
            let reading = try answer.startReading()
            let ask = try #require(try start.asks(for: answer).first, "\(answer.when) names no station")
            for reply in try answer.startReplies() {
                count += 1
                let stubReply = reply.stubReply
                let starter = ServerLiveActivityStarter(server: .test, httpClient: ServerStubHTTPClient { _ in stubReply })
                let read = await starter.start(stationId: ask.station, startToken: ask.startToken)
                if read.startsTheLiveActivity != (reading == .start) {
                    problems.append("\(answer.when), \(reply.shown.joined(separator: ", ")): reads \(read.summary)")
                }
            }
        }

        #expect(count > 0)
        let shown = problems.prefix(8).joined(separator: "\n")
        #expect(problems.isEmpty, "\(problems.count) of \(count) replies are not read as the set says:\n\(shown)")
    }

    private static func shape(of station: String) -> String {
        String(station.map { $0.isNumber ? "#" : $0 })
    }
}
