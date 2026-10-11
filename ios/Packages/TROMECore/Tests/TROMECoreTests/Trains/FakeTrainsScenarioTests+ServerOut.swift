import Foundation
import Testing
@testable import TROMECore

extension FakeTrainsScenarioTests {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func departures(_ scenario: FakeTrainsScenario, at start: Date, afterMinutes minutes: Double)
        async throws -> [Departure] {
        let station = try #require(try StationCatalog.bundled().stations.first { $0.name == "Abbesses" })
        let now = start.addingTimeInterval(minutes * 60)
        return try await FakeDeparturesProvider(scenario: scenario, start: start, now: { now })
            .departures(at: [station])
    }

    @Test func givesTimesThenSaysTheServerIsOutUntilEightMinutesAfterTheLaunchThenGivesTimesAgain() async throws {
        let start = Fixture.date("2026-10-02T08:30:00Z")

        #expect(try await !departures(.serverOut, at: start, afterMinutes: 0.9).isEmpty)
        for minutes in [1.0, 4, 7.9] {
            await #expect(throws: NextTrainsError.serverOut(retryAt: Fixture.date("2026-10-02T08:38:00Z"))) {
                try await departures(.serverOut, at: start, afterMinutes: minutes)
            }
        }
        #expect(try await !departures(.serverOut, at: start, afterMinutes: 8).isEmpty)
    }

    @Test func givesTimesThenRefusesTheAppTokenFromOneMinuteAfterTheLaunch() async throws {
        let start = Fixture.date("2026-10-02T08:30:00Z")

        #expect(try await !departures(.appTokenRefused, at: start, afterMinutes: 0.9).isEmpty)
        for minutes in [1.0, 8, 60] {
            await #expect(throws: NextTrainsError.appTokenRefused) {
                try await departures(.appTokenRefused, at: start, afterMinutes: minutes)
            }
        }
    }

    @Test func saysTheServerIsOutFromTheLaunchUntilJustAfterMidnight() {
        let start = Fixture.date("2026-10-02T20:30:00Z")
        let retryAt = Fixture.date("2026-10-02T22:00:40Z")

        #expect(FakeTrainsScenario.serverOutUntilTomorrow.serverRetryAt(from: start, now: start, calendar: paris)
            == retryAt)
        #expect(FakeTrainsScenario.serverOutUntilTomorrow.serverRetryAt(from: start, now: retryAt, calendar: paris)
            == nil)
    }
}
