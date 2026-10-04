import Foundation
import Synchronization
import Testing
@testable import TROMECore

private final class CallTimes: Sendable {
    private let times = Mutex<[Date]>([])

    var all: [Date] {
        times.withLock { $0 }
    }

    func record(_ date: Date) {
        times.withLock { $0.append(date) }
    }
}

extension AutoLiveActivityModelTests {
    private func answerServerOut(for retryDelay: TimeInterval) -> CallTimes {
        let callTimes = CallTimes()
        let clock = clock
        provider.answer(for: Places.stationA) {
            callTimes.record(clock.now)
            return .failure(.serverOut(retryAt: clock.now.addingTimeInterval(retryDelay)))
        }
        return callTimes
    }

    private func gaps(between times: [Date]) -> [TimeInterval] {
        zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }
    }

    @Test func asksTheServerAgainOnlyAtEachRetryTimeWhileTheAppIsOnScreen() async {
        let callTimes = answerServerOut(for: 1_840)
        clock.letTimersFire(upTo: 1_840)
        let model = makeModel()

        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { provider.callCount >= 3 }

        let times = callTimes.all
        #expect(times.count >= 3)
        #expect(gaps(between: times).allSatisfy { $0 == 1_840 })
        #expect(client.shownContent?.trains == .noData)
        #expect(client.shownContent?.serverIsOut == true)
    }

    @Test func asksTheServerAgainOnlyAtEachRetryTimeInTheBackground() async {
        let callTimes = answerServerOut(for: 1_840)
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.shownContent?.serverIsOut == true }
        model.setAppPhase(.background)

        clock.letTimersFire(upTo: 1_840)
        await waitUntil { provider.callCount >= 3 }

        let times = callTimes.all
        #expect(times.count >= 3)
        #expect(gaps(between: times).allSatisfy { $0 == 1_840 })
    }

    @Test func showsWhatTheServerGivesAtTheRetryTimeOnceTheTimesComeBack() async {
        let clock = clock
        let retryAt = clock.now.addingTimeInterval(1_840)
        let callTimes = CallTimes()
        provider.answer(for: Places.stationA) {
            callTimes.record(clock.now)
            return clock.now < retryAt ? .failure(.serverOut(retryAt: retryAt)) : .success([])
        }
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        await waitUntil { client.shownContent?.serverIsOut == true }
        model.setAppPhase(.background)

        clock.letTimersFire(upTo: 1_840)
        await waitUntil { client.shownContent?.serverIsOut == false }

        #expect(callTimes.all.prefix(2).last == retryAt)
        #expect(client.shownContent?.serverIsOut == false)
        #expect(client.shownContent?.trains != .noData)
    }
}
