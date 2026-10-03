import Foundation
import Testing
@testable import TROMECore

struct AutomaticModeTests {
    private static let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    private let calendar = Self.paris
    private let now = Self.paris.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 18, minute: 40)) ?? .now

    private static let snoozeLengths: [(SnoozeDuration, TimeInterval)] = [
        (.thirtyMinutes, 1_800),
        (.oneHour, 3_600),
        (.restOfToday, 19_200)
    ]

    @Test(arguments: snoozeLengths)
    func snoozesUntilTheEndOfTheChosenDuration(duration: SnoozeDuration, seconds: TimeInterval) {
        let mode = AutomaticMode.turnedOn.snoozed(for: duration, now: now, calendar: calendar)

        #expect(mode == .snoozed(until: now.addingTimeInterval(seconds)))
    }

    @Test func snoozesForTheRestOfTodayUntilMidnightOnTheDayTheClocksGoBack() {
        let clocksGoBack = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 1)) ?? now

        let mode = AutomaticMode.turnedOn.snoozed(for: .restOfToday, now: clocksGoBack, calendar: calendar)

        #expect(mode == .snoozed(until: clocksGoBack.addingTimeInterval(24 * 3_600)))
    }

    @Test func snoozesAgainFromNowWhenAlreadySnoozed() {
        let mode = AutomaticMode.snoozed(until: now.addingTimeInterval(60))
            .snoozed(for: .oneHour, now: now, calendar: calendar)

        #expect(mode == .snoozed(until: now.addingTimeInterval(3_600)))
    }

    @Test func staysOffWhenSnoozedWhileOff() {
        #expect(AutomaticMode.turnedOff.snoozed(for: .oneHour, now: now, calendar: calendar) == .turnedOff)
    }

    @Test func isOnAgainOnceTheSnoozeEnds() {
        let mode = AutomaticMode.snoozed(until: now)

        #expect(mode.current(at: now.addingTimeInterval(-1)) == mode)
        #expect(mode.current(at: now) == .turnedOn)
    }

    @Test func allowsAutomaticStartOnlyWhenOn() {
        #expect(AutomaticMode.turnedOn.allowsAutomaticStart)
        #expect(AutomaticMode.snoozed(until: now).allowsAutomaticStart == false)
        #expect(AutomaticMode.turnedOff.allowsAutomaticStart == false)
    }
}
