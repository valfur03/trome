import Foundation
import Testing
@testable import TROMECore

struct LiveTimesComeBackTests {
    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    @Test func givesTheRetryTimeWhenItIsTheSameDay() {
        let retryAt = Fixture.date("2026-10-02T09:00:40Z")

        let comeBack = LiveTimesComeBack(
            retryAt: retryAt, now: Fixture.date("2026-10-02T08:30:00Z"), calendar: calendar("Europe/Paris")
        )

        #expect(comeBack == .around(retryAt))
    }

    @Test func saysTomorrowWhenTheRetryTimeIsOnTheNextDay() {
        let comeBack = LiveTimesComeBack(
            retryAt: Fixture.date("2026-10-02T22:00:40Z"),
            now: Fixture.date("2026-10-02T19:30:00Z"),
            calendar: calendar("Europe/Paris")
        )

        #expect(comeBack == .tomorrow)
    }

    @Test func countsTheDayInThePhoneTimeZone() {
        let retryAt = Fixture.date("2026-10-02T22:00:40Z")

        let comeBack = LiveTimesComeBack(
            retryAt: retryAt, now: Fixture.date("2026-10-02T19:30:00Z"), calendar: calendar("America/New_York")
        )

        #expect(comeBack == .around(retryAt))
    }
}
