import Foundation

public enum DepartureTime {
    public static func minutes(until time: Date, from now: Date) -> Int {
        max(0, Int((time.timeIntervalSince(now) / 60).rounded(.down)))
    }
}
