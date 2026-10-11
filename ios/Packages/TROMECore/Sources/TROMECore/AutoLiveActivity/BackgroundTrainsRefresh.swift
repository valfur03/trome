import Foundation

public enum BackgroundTrainsRefresh {
    public static let minimumDelay: TimeInterval = 30
    public static let maximumDelay: TimeInterval = 120
    public static let delayAfterDeparture: TimeInterval = 5
    static let launchDelay: TimeInterval = 3
    /// How long a call made in place of a redraw waits for its answer before the redraw happens anyway.
    static let answerWaitInPlaceOfARedraw: TimeInterval = 2

    public static func delay(untilStale staleDate: Date?, now: Date) -> TimeInterval {
        guard let staleDate else { return maximumDelay }
        let untilDeparture = staleDate.timeIntervalSince(now) + delayAfterDeparture
        return min(max(untilDeparture, minimumDelay), maximumDelay)
    }

    static func nextCall(after state: NextTrainsState, untilStale staleDate: Date?, now: Date) -> Date {
        if let retryAt = state.serverRetryAt, retryAt > now {
            return retryAt
        }
        return now.addingTimeInterval(delay(untilStale: staleDate, now: now))
    }

    /// Whether the redraw at the departure of a train asks for new times instead, when it would leave a row with
    /// fewer trains: the next train of that row then comes with the same update, not a few seconds later.
    /// The call keeps the minimum delay after the last one, and never comes before the retry time of a server
    /// that is out.
    static func asksInsteadOfRedrawing(
        losesATrain: Bool,
        after state: NextTrainsState,
        lastCall: Date,
        now: Date
    ) -> Bool {
        guard losesATrain, now >= lastCall.addingTimeInterval(minimumDelay) else { return false }
        return state.serverRetryAt.map { $0 <= now } ?? true
    }

    public static func shouldAskAgain(after state: NextTrainsState) -> Bool {
        switch state {
        case .missingKey, .failed(.keyRejected), .failed(.quotaExceeded), .failed(.appTokenRefused):
            false
        default:
            true
        }
    }
}
