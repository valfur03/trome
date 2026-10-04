import Foundation

public enum LiveTimesComeBack: Equatable, Sendable {
    case around(Date)
    case tomorrow

    public init(retryAt: Date, now: Date, calendar: Calendar = .current) {
        self = calendar.isDate(retryAt, inSameDayAs: now) ? .around(retryAt) : .tomorrow
    }
}
