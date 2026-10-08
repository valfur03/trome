import Foundation
import Testing
@testable import TROMECore

/// A stop of the station did not answer while another one did: the direction of that stop must never
/// say "no train", because the app does not know its trains.
extension PRIMDeparturesProviderTests {
    enum StopFailure: CaseIterable, Sendable {
        case serverOut
        case noNetwork
    }

    static let aubervilliersQuay = "STIF:StopPoint:Q:22059:"
    static let quayWithNoTrain = "no-quay"

    /// The recorded answer of Abbesses, cut to the trains of the asked quay, or a failure for `failedQuay`.
    static func quayReply(
        to request: URLRequest,
        failing failure: StopFailure? = nil,
        at failedQuay: String = aubervilliersQuay,
        emptyQuay: String? = nil
    ) throws -> ServerStubHTTPClient.Reply {
        let quay = request.url?.pathComponents.dropLast().last ?? ""
        if quay == failedQuay, let failure {
            switch failure {
            case .serverOut: return outReply()
            case .noNetwork: throw URLError(.notConnectedToInternet)
            }
        }
        let body = try answer(
            Fixture.data("stop-monitoring-abbesses-stop-area"),
            onlyAt: quay == emptyQuay ? quayWithNoTrain : quay
        )
        return .init(
            body: body,
            status: 200,
            headers: ["Content-Type": "application/json", "Last-Modified": lastModified]
        )
    }

    static func showsNoTrain(_ direction: LineDirection) -> Bool {
        direction.trains.isEmpty && !direction.nextTrainIsOverAnHourAway && !direction.hasNoAnswer
    }

    func shownDirections(of answer: DeparturesAnswer, at station: Station) -> [LineDirection] {
        let board = DepartureBoard(
            departures: answer.departures,
            stations: [station],
            now: Self.recordedAt,
            unansweredStops: answer.unansweredStops
        )
        let content = StationActivityAttributes.ContentState(
            station: station,
            trains: .departures(board, updatedAt: Self.recordedAt),
            now: Self.recordedAt
        )
        return content.trains.linesPage?.lines.flatMap(\.directions) ?? []
    }

    @Test(arguments: StopFailure.allCases)
    func neverSaysNoTrainTowardAStopThatDidNotAnswerWhileAnotherStopAnswered(failure: StopFailure) async throws {
        let (provider, _) = serverProvider { try Self.quayReply(to: $0, failing: failure) }

        let answer = try await provider.departuresAnswer(at: [abbessesByQuay])
        let directions = shownDirections(of: answer, at: abbessesByQuay)

        #expect(answer.unansweredStops == [Self.aubervilliersQuay])
        #expect(directions.map(\.label) == ["Mairie d'Aubervilliers", "Mairie d'Issy"])
        #expect(!directions.contains(where: Self.showsNoTrain))
        #expect(directions.map(\.hasNoAnswer) == [true, false])
        #expect(directions.map(\.trains.count) == [0, 2])
    }

    @Test func stillSaysNoTrainTowardAStopThatAnsweredWithNoTrain() async throws {
        let (provider, _) = serverProvider { try Self.quayReply(to: $0, emptyQuay: Self.aubervilliersQuay) }

        let answer = try await provider.departuresAnswer(at: [abbessesByQuay])
        let directions = shownDirections(of: answer, at: abbessesByQuay)

        #expect(answer.unansweredStops.isEmpty)
        #expect(directions.map(\.label) == ["Mairie d'Aubervilliers", "Mairie d'Issy"])
        #expect(directions.map(Self.showsNoTrain) == [true, false])
    }
}
