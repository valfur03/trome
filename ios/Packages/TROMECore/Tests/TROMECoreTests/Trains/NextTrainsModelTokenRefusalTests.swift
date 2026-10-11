import Foundation
import Synchronization
import Testing
@testable import TROMECore

@MainActor
struct NextTrainsModelTokenRefusalTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line12 = TransitLine(mode: .metro, name: "12")
    private let provider = StubDeparturesProvider()
    private var abbesses: Station {
        Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [line12])
    }
    private var pigalle: Station {
        Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [line12])
    }

    private func makeModel(sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }) -> NextTrainsModel {
        NextTrainsModel(provider: provider, now: { [now] in now }, sleep: sleep)
    }

    /// A sleep that lets the loop go round `rounds` times, then stops it.
    private func sleep(rounds: Int) -> @Sendable (Duration) async throws -> Void {
        let sleeps = Mutex(0)
        return { _ in
            let count = sleeps.withLock { count in
                count += 1
                return count
            }
            if count >= rounds {
                throw CancellationError()
            }
        }
    }

    @Test func asksOnceWhileItKeepsUpdatingAfterARefusalOfTheToken() async {
        provider.answer(.failure(.appTokenRefused), for: abbesses)
        let model = makeModel(sleep: sleep(rounds: 10))

        await model.keepUpdated(for: abbesses)

        #expect(provider.callCount == 1)
        #expect(model.state == .failed(.appTokenRefused))
    }

    @Test(arguments: [
        NextTrainsError.unreachable,
        .serviceFailure,
        .serverOut(retryAt: Date(timeIntervalSince1970: 1_000_000 + 60))
    ])
    func keepsAskingAfterAnyOtherFailure(error: NextTrainsError) async {
        provider.answer(.failure(error), for: abbesses)
        let model = makeModel(sleep: sleep(rounds: 3))

        await model.keepUpdated(for: abbesses)

        #expect(provider.callCount == 3)
    }

    @Test func makesNoCallForAnotherStationAfterARefusal() async {
        provider.answer(.failure(.appTokenRefused), for: abbesses)
        let model = makeModel()
        await model.refresh(for: abbesses)

        await model.refresh(for: pigalle)

        #expect(provider.callCount == 1)
        #expect(model.state(for: pigalle) == .failed(.appTokenRefused))
    }

    @Test func asksAgainOnceAllowedAndShowsTheTimesWhenTheServerAcceptsTheToken() async {
        provider.answer(.failure(.appTokenRefused), for: abbesses)
        let model = makeModel()
        await model.refresh(for: abbesses)
        provider.answer(.success([]), for: abbesses)

        model.askAgainAfterARefusal()
        await model.refresh(for: abbesses)

        #expect(provider.callCount == 2)
        #expect(model.state == .noLiveData)
    }
}
