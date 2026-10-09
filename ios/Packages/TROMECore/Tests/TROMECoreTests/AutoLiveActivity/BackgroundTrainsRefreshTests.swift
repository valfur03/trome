import Foundation
import Testing
@testable import TROMECore

struct BackgroundTrainsRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func asksAgainJustAfterTheFirstShownTrainLeaves() {
        let delay = BackgroundTrainsRefresh.delay(untilStale: now.addingTimeInterval(60), now: now)

        #expect(delay == 60 + BackgroundTrainsRefresh.delayAfterDeparture)
    }

    @Test func waitsAtLeastTheMinimumDelay() {
        let delay = BackgroundTrainsRefresh.delay(untilStale: now.addingTimeInterval(3), now: now)

        #expect(delay == BackgroundTrainsRefresh.minimumDelay)
    }

    @Test(arguments: [Date(timeIntervalSince1970: 1_000_000 + 600), nil])
    func waitsAtMostTheMaximumDelay(staleDate: Date?) {
        #expect(BackgroundTrainsRefresh.delay(untilStale: staleDate, now: now) == BackgroundTrainsRefresh.maximumDelay)
    }

    @Test(arguments: [NextTrainsState.missingKey, .failed(.keyRejected), .failed(.quotaExceeded)])
    func stopsAskingWhenAskingAgainCannotHelp(state: NextTrainsState) {
        #expect(BackgroundTrainsRefresh.shouldAskAgain(after: state) == false)
    }

    @Test(arguments: [
        NextTrainsState.noLiveData,
        .failed(.unreachable),
        .failed(.serviceFailure),
        .failed(.serverOut(retryAt: Date(timeIntervalSince1970: 1_000_000 + 1_840)))
    ])
    func asksAgainAfterAPassingProblem(state: NextTrainsState) {
        #expect(BackgroundTrainsRefresh.shouldAskAgain(after: state))
    }

    @Test func asksTheServerAgainOnlyAtTheRetryTimeItGave() {
        let retryAt = now.addingTimeInterval(1_840)

        let nextCall = BackgroundTrainsRefresh.nextCall(
            after: .failed(.serverOut(retryAt: retryAt)),
            untilStale: now.addingTimeInterval(60),
            now: now
        )

        #expect(nextCall == retryAt)
    }

    @Test(arguments: [
        NextTrainsState.failed(.serviceFailure),
        .failed(.serverOut(retryAt: Date(timeIntervalSince1970: 1_000_000)))
    ])
    func asksAgainAfterTheUsualDelayWhenTheServerGaveNoRetryTimeAhead(state: NextTrainsState) {
        let nextCall = BackgroundTrainsRefresh.nextCall(after: state, untilStale: now.addingTimeInterval(60), now: now)

        #expect(nextCall == now.addingTimeInterval(60 + BackgroundTrainsRefresh.delayAfterDeparture))
    }

    @Test func asksInsteadOfRedrawingWhenARowWouldLoseATrainLongEnoughAfterTheLastCall() {
        let asks = BackgroundTrainsRefresh.asksInsteadOfRedrawing(
            losesATrain: true,
            after: .failed(.unreachable),
            lastCall: now.addingTimeInterval(-BackgroundTrainsRefresh.minimumDelay),
            now: now
        )

        #expect(asks)
    }

    @Test(arguments: [
        (false, -60.0, nil as TimeInterval?),
        (true, -29.0, nil),
        (true, -60.0, 1_840.0)
    ])
    func redrawsWithoutAskingOtherwise(losesATrain: Bool, lastCall: TimeInterval, retryIn: TimeInterval?) {
        let state: NextTrainsState = retryIn.map { .failed(.serverOut(retryAt: now.addingTimeInterval($0))) }
            ?? .failed(.unreachable)

        let asks = BackgroundTrainsRefresh.asksInsteadOfRedrawing(
            losesATrain: losesATrain,
            after: state,
            lastCall: now.addingTimeInterval(lastCall),
            now: now
        )

        #expect(!asks)
    }
}
