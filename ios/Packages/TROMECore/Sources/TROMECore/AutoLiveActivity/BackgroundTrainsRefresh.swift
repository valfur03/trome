import Foundation

public enum BackgroundTrainsRefresh {
    public static let minimumDelay: TimeInterval = 30
    public static let maximumDelay: TimeInterval = 120
    public static let delayAfterDeparture: TimeInterval = 5
    static let launchDelay: TimeInterval = 3

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

    public static func shouldAskAgain(after state: NextTrainsState) -> Bool {
        switch state {
        case .missingKey, .failed(.keyRejected), .failed(.quotaExceeded):
            false
        default:
            true
        }
    }
}
