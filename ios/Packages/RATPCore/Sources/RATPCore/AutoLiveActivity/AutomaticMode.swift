import Foundation

public enum SnoozeDuration: String, CaseIterable, Codable, Sendable {
    case thirtyMinutes
    case oneHour
    case restOfToday

    func end(from now: Date, calendar: Calendar) -> Date {
        switch self {
        case .thirtyMinutes:
            now.addingTimeInterval(30 * 60)
        case .oneHour:
            now.addingTimeInterval(60 * 60)
        case .restOfToday:
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        }
    }
}

public enum AutomaticMode: Codable, Equatable, Sendable {
    case turnedOn
    case snoozed(until: Date)
    case turnedOff

    var allowsAutomaticStart: Bool {
        self == .turnedOn
    }

    func current(at now: Date) -> AutomaticMode {
        guard case .snoozed(let end) = self, end <= now else { return self }
        return .turnedOn
    }

    func snoozed(for duration: SnoozeDuration, now: Date, calendar: Calendar) -> AutomaticMode {
        guard self != .turnedOff else { return .turnedOff }
        return .snoozed(until: duration.end(from: now, calendar: calendar))
    }
}
