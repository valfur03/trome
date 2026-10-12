import Foundation
import Synchronization
import Testing
@testable import TROMECore

/// The newest recorded set of promises of `contracts/builds/` is true of the app code: the app sends the request of
/// the set, asks only for stops of the shapes that it names, and reads each promised answer as the set says.
/// Why: the set of a new build is copied from the newest one at its upload, and the server is judged against it
/// (`make server-check`); a set that the app code does not keep lets the server check pass while that build breaks.
struct BuildPromisesTests {
    static let newest = Result { try BuildPromiseSet.newest() }
    static let answerNames = (try? newest.get())?.answers.map(\.when) ?? []

    @Test func readsTheNewestSet() throws {
        let set = try Self.newest.get()
        #expect(!set.builds.isEmpty, "\(set.name) names no build")
        #expect(set.builds.allSatisfy { BuildNumber($0) != nil }, "\(set.name) names its builds as the release guide")
        #expect(!set.stops.isEmpty && !set.answers.isEmpty, "\(set.name) promises no stop or no answer")
        #expect(Set(Self.answerNames).count == Self.answerNames.count, "two answers of \(set.name) have one \"when\"")
    }

    @Test func theNewestBuildHasTheHighestVersionThenTheHighestNumber() throws {
        #expect(try #require(BuildNumber("1.0.0 (10)")) > #require(BuildNumber("1.0.0 (9)")))
        #expect(try #require(BuildNumber("1.1.0 (1)")) > #require(BuildNumber("1.0.0 (12)")))
        #expect(try #require(BuildNumber("1.10 (1)")) > #require(BuildNumber("1.9.9 (1)")))
        #expect(BuildNumber("1.0.0") == nil)
    }

    @Test func sendsTheRequestOfTheSetForEveryStop() async throws {
        let set = try Self.newest.get()
        let headers = Dictionary(uniqueKeysWithValues: set.request.headers.map { name, value in
            (name.lowercased(), set.requestHeader(value))
        })
        for stop in set.stops {
            let client = ServerStubHTTPClient { _ in .init(body: Data(), status: 503, headers: [:]) }
            let provider = PRIMDeparturesProvider(source: .server(.test), httpClient: client)
            _ = try? await provider.stopAnswer(at: stop.stop)
            let request = try #require(client.requests.first)
            let url = try #require(request.url)
            let sent = Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { name, value in
                (name.lowercased(), value)
            })

            #expect(request.httpMethod == set.request.method, "\(stop.stop)")
            #expect(url.scheme == "https" && url.host() == "trains.example.com" && url.query() == nil, "\(url)")
            let path = set.request.path.replacingOccurrences(of: "<STOP>", with: stop.stop)
            #expect(url.path(percentEncoded: true) == path)
            #expect(sent == headers, "\(stop.stop)")
            #expect(request.timeoutInterval == set.app.waitForOneAnswerSeconds, "\(stop.stop)")
        }
    }

    @Test func asksOnlyForStopsOfAShapeThatTheSetPromises() throws {
        let set = try Self.newest.get()
        let stations = try StationCatalog.bundled().stations
        let asked = Set(PRIMDeparturesProvider.stopRequests(for: stations).map { Self.shape(of: $0.monitoringRef) })
        let promised = Set(set.stops.map { Self.shape(of: $0.stop) })

        #expect(!asked.isEmpty)
        #expect(asked.subtracting(promised).isEmpty, "\(set.name) promises only the shapes \(promised.sorted())")
    }

    @Test @MainActor func asksAsOftenAsTheSetSays() throws {
        let set = try Self.newest.get()

        #expect(NextTrainsModel.refreshInterval == .seconds(set.app.askEverySeconds))
    }

    @Test(arguments: answerNames)
    func readsTheAnswerAsTheSetSays(when: String) async throws {
        let set = try Self.newest.get()
        let answer = try #require(set.answers.first { $0.when == when })
        let reading = try answer.reading()
        var problems: [String] = []
        var count = 0
        for stop in try answer.stops(of: set) {
            for reply in try answer.replies(at: stop, of: set) {
                count += 1
                if let problem = await Self.problem(reading: reply, as: reading, at: stop.stop, of: set) {
                    problems.append("\(stop.stop), \(reply.shown.joined(separator: ", ")): \(problem)")
                }
            }
        }

        #expect(count > 0)
        let shown = problems.prefix(8).joined(separator: "\n")
        #expect(problems.isEmpty, "\(problems.count) of \(count) replies are not read as \(reading):\n\(shown)")
    }

    private static func shape(of stop: String) -> String {
        String(stop.map { $0.isNumber ? "#" : $0 })
    }

    private static func problem(
        reading reply: PromisedReply,
        as reading: PromisedReading,
        at stop: String,
        of set: BuildPromiseSet
    ) async -> String? {
        let clock = PromiseClock(PromisedReply.now)
        let stubReply = reply.stubReply
        let client = ServerStubHTTPClient { _ in stubReply }
        let provider = PRIMDeparturesProvider(source: .server(.test), httpClient: client, now: { clock.now })
        let outcome = await Self.outcome(of: provider, at: stop)
        switch reading {
        case .times:
            return Self.timesProblem(outcome, reply: reply)
        case .refusal:
            return Self.errorProblem(outcome, expected: .appTokenRefused)
        case .out, .failure:
            guard let retryAt = reply.retryAt else { return "the reply gives no retry time" }
            let retry = max(retryAt, PromisedReply.now.addingTimeInterval(set.app.shortestWaitAfterAnOutAnswerSeconds))
            let expected = reading == .out ? NextTrainsError.serverOut(retryAt: retry) : .serviceFailure
            if let problem = Self.errorProblem(outcome, expected: expected) {
                return problem
            }
            clock.now = retry.addingTimeInterval(-1)
            let early = await Self.outcome(of: provider, at: stop)
            guard client.requests.count == 1, Self.errorProblem(early, expected: expected) == nil else {
                return "asks the server again before the retry time \(retry)"
            }
            clock.now = retry
            _ = await Self.outcome(of: provider, at: stop)
            return client.requests.count == 2 ? nil : "does not ask the server again at the retry time \(retry)"
        }
    }

    private static func outcome(
        of provider: PRIMDeparturesProvider,
        at stop: String
    ) async -> Result<PRIMDeparturesProvider.StopAnswer, any Error> {
        do {
            return .success(try await provider.stopAnswer(at: stop))
        } catch {
            return .failure(error)
        }
    }

    private static func timesProblem(
        _ outcome: Result<PRIMDeparturesProvider.StopAnswer, any Error>,
        reply: PromisedReply
    ) -> String? {
        let visits = reply.primAnswer.flatMap { try? StopMonitoringResponse.visits(from: $0) }
        switch outcome {
        case .failure(let error):
            return "reads \(error), not the times"
        case .success(let answer) where answer.visits != visits:
            return "reads \(answer.visits.count) trains, not the \(visits?.count ?? 0) trains of the PRIM answer"
        case .success(let answer) where answer.answeredAt != reply.answeredAt:
            return "reads the time of the answer as \(String(describing: answer.answeredAt))"
        case .success:
            return nil
        }
    }

    private static func errorProblem(
        _ outcome: Result<PRIMDeparturesProvider.StopAnswer, any Error>,
        expected: NextTrainsError
    ) -> String? {
        switch outcome {
        case .success:
            "reads the times, not \(expected)"
        case .failure(let error as NextTrainsError) where error == expected:
            nil
        case .failure(let error):
            "reads \(error), not \(expected)"
        }
    }
}

/// The time of the app, which the test moves to the retry time of an answer.
private final class PromiseClock: Sendable {
    private let time: Mutex<Date>

    init(_ time: Date) {
        self.time = Mutex(time)
    }

    var now: Date {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }
}
