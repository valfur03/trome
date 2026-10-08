import Foundation
import Synchronization
import Testing
@testable import TROMECore

/// A stop of the station did not answer while another one did: the direction of that stop keeps the times
/// of an earlier answer while their first train has not left, else it shows an empty box.
extension NextTrainsModelTests {
    private final class Server: Sendable {
        private let date = Mutex(Fixture.date("2026-09-26T10:00:00Z"))
        private let aubervilliersIsOut = Mutex(false)

        var now: Date {
            date.withLock { $0 }
        }

        func set(_ time: String) {
            date.withLock { $0 = Fixture.date(time) }
        }

        func takeAubervilliersOut() {
            aubervilliersIsOut.withLock { $0 = true }
        }

        func reply(to request: URLRequest) throws -> ServerStubHTTPClient.Reply {
            let isOut = aubervilliersIsOut.withLock { $0 }
            return try PRIMDeparturesProviderTests.quayReply(to: request, failing: isOut ? .serverOut : nil)
        }
    }

    private var abbessesByQuay: Station {
        PRIMDeparturesProviderTests().abbessesByQuay
    }

    private func model(of server: Server) -> NextTrainsModel {
        let client = ServerStubHTTPClient { try server.reply(to: $0) }
        let provider = PRIMDeparturesProvider(source: .server(.test), httpClient: client, now: { server.now })
        return NextTrainsModel(provider: provider, now: { server.now })
    }

    private func aubervilliersDirection(of state: NextTrainsState, at time: String) throws -> LineDirection {
        let content = StationActivityAttributes.ContentState(
            station: abbessesByQuay,
            trains: state,
            now: Fixture.date(time)
        )
        let directions = content.trains.linesPage?.lines.flatMap(\.directions) ?? []
        return try #require(directions.first { $0.label == "Mairie d'Aubervilliers" })
    }

    @Test func keepsTheEarlierTimesOfADirectionWhoseStopDidNotAnswerUntilTheirFirstTrainHasLeft() async throws {
        let server = Server()
        let model = model(of: server)
        await model.refresh(for: abbessesByQuay)
        server.takeAubervilliersOut()
        server.set("2026-09-26T10:01:00Z")

        await model.refresh(for: abbessesByQuay)
        let countingDown = try aubervilliersDirection(of: model.state, at: "2026-09-26T10:01:00Z")
        let afterTheFirstTrain = try aubervilliersDirection(of: model.state, at: "2026-09-26T10:04:30Z")
        server.set("2026-09-26T10:05:00Z")
        await model.refresh(for: abbessesByQuay)
        let stillOut = try aubervilliersDirection(of: model.state, at: "2026-09-26T10:05:00Z")

        #expect(countingDown.times == [Fixture.date("2026-09-26T10:04:00Z"), Fixture.date("2026-09-26T10:09:30Z")])
        #expect(!countingDown.hasNoAnswer)
        #expect(afterTheFirstTrain.trains.isEmpty && afterTheFirstTrain.hasNoAnswer)
        #expect(stillOut.trains.isEmpty && stillOut.hasNoAnswer)
    }

    @Test func showsAnEmptyBoxTowardTheEndOfTheLineWhenItHoldsNoEarlierTimes() async throws {
        let server = Server()
        server.takeAubervilliersOut()
        let model = model(of: server)

        await model.refresh(for: abbessesByQuay)
        let direction = try aubervilliersDirection(of: model.state, at: "2026-09-26T10:00:00Z")

        #expect(direction.name == "Mairie d'Aubervilliers")
        #expect(direction.trains.isEmpty)
        #expect(direction.hasNoAnswer)
        #expect(!direction.nextTrainIsOverAnHourAway)
    }
}
