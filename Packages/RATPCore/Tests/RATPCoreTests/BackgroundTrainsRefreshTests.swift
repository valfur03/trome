import Foundation
import Testing
@testable import RATPCore

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
}
