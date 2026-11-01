import Foundation

/// The background time that iOS still gives the app (`UIApplication.backgroundTimeRemaining`), as the record says it.
/// iOS gives a huge number when the app has no limit, for example on screen.
public enum BackgroundTime {
    public static func line(remaining: TimeInterval) -> String {
        guard remaining.isFinite, remaining < 100_000 else { return "no background time limit" }
        return "\(Int(max(0, remaining))) s of background time left"
    }
}
