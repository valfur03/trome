import Foundation

/// When iOS saw the crossing of a station area, and how late it gave it to the app, as the Wake log writes it.
/// Why: the position of a wake line is the last one that iOS had, so its age says nothing of the crossing; a walk
/// with no line until the rider opened the app reads from this time whether iOS had seen the entry and kept it
/// (seen minutes before, given at the open) or had not seen it yet (seen and given at the open).
public enum RegionCrossingTime {
    /// The time of an event of iOS, or nil when iOS gave none: the date of an event is never empty, but one at or
    /// before the reference date of the platform (1 January 2001) is the default of a date that nobody set.
    public static func seen(_ date: Date) -> Date? {
        date > Date(timeIntervalSinceReferenceDate: 0) ? date : nil
    }

    /// "seen 18:41:03, given 8 min later", "seen 18:41:03, given at once" (under a second), or "no time from iOS".
    static func line(seenAt: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let seenAt else { return "no time from iOS" }
        let delay = now.timeIntervalSince(seenAt)
        let given = delay < 1 ? "given at once" : "given \(WakeProcess.duration(delay)) later"
        return "seen \(WakeLogClock(timeZone: timeZone).time(seenAt, now: now)), \(given)"
    }
}

/// The time of a Wake log line part, with its day only when it is not the day of the line.
struct WakeLogClock {
    private let time: DateFormatter
    private let dayAndTime: DateFormatter
    private let calendar: Calendar

    init(timeZone: TimeZone) {
        time = Self.formatter("HH:mm:ss", timeZone: timeZone)
        dayAndTime = Self.formatter("d MMM HH:mm:ss", timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func time(_ date: Date, now: Date) -> String {
        calendar.isDate(date, inSameDayAs: now) ? time.string(from: date) : dayAndTime.string(from: date)
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
