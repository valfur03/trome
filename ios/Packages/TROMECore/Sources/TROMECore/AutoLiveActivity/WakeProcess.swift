import Foundation

/// What a walk cannot see from the times alone: whether iOS launched the app for an event of a watched area, or the
/// event came to a process that was already running (resumed from a suspension, or kept running by the location).
/// A fresh launch is the first event of the process, at most `freshLaunchWindow` after its start: an app that the
/// rider opened and that gets its first event later is told as already running.
public struct WakeProcess: Sendable {
    public static let freshLaunchWindow: TimeInterval = 30

    private let launchedAt: Date
    private var events = 0

    public init(launchedAt: Date) {
        self.launchedAt = launchedAt
    }

    /// The part of a wake line that says it, counting this event as one more of the process.
    public mutating func line(now: Date) -> String {
        events += 1
        let seconds = max(0, now.timeIntervalSince(launchedAt))
        if events == 1, seconds <= Self.freshLaunchWindow {
            return "fresh launch, \(Int(seconds)) s ago"
        }
        return "app already running for \(Self.duration(seconds))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        if whole < 120 {
            return "\(whole) s"
        }
        if whole < 7_200 {
            return "\(whole / 60) min"
        }
        return "\(whole / 3_600) h \(String(format: "%02d", whole % 3_600 / 60)) min"
    }
}
