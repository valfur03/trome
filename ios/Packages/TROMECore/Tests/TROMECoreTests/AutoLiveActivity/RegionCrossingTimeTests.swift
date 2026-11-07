import Foundation
import Testing
@testable import TROMECore

/// A walk tells a crossing that iOS saw minutes before the rider opened the app from one that iOS reported at that
/// moment, and reads what iOS still holds for the nearest station when the app may be suspended.
@Suite(.bounded)
struct RegionCrossingTimeTests {
    typealias Places = AutoTestPlaces

    /// 18:49:13 on the walk of 2026-11-02, the time of the open at Le Parc de Saint-Maur, in GMT.
    private let opened = Self.time(18, 49, 13)

    private static func time(_ hour: Int, _ minute: Int, _ second: Int, day: Int = 2) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: parts)!
    }

    private func line(_ event: RegionEvent, seenAt: Date?) -> String {
        let fix = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: opened)
        return event.wakeLine(phoneAt: fix, seenAt: seenAt, now: opened, catalog: Places.catalog, timeZone: .gmt)
    }

    // MARK: - When iOS saw a crossing (AC1)

    @Test func saysThatIOSSawAnEntryMinutesBeforeItGaveIt() {
        let line = line(.entered(regionId: "arrival:a"), seenAt: Self.time(18, 41, 3))

        #expect(line == "iOS: entered Station A (phone 50 m away, ±10 m, 0 s old), seen 18:41:03, given 8 min later")
    }

    @Test func saysThatIOSGaveAnEntryAtOnce() {
        let line = line(.entered(regionId: "arrival:a"), seenAt: opened - 0.4)

        #expect(line == "iOS: entered Station A (phone 50 m away, ±10 m, 0 s old), seen 18:49:12, given at once")
    }

    @Test func saysWhenIOSGaveNoTimeForAnEntry() {
        let line = line(.entered(regionId: "arrival:a"), seenAt: nil)

        #expect(line == "iOS: entered Station A (phone 50 m away, ±10 m, 0 s old), no time from iOS")
    }

    @Test func saysThatIOSSawAnExitSecondsBeforeItGaveIt() {
        let line = line(.left(regionId: "arrival:a"), seenAt: opened - 42)

        #expect(line == "iOS: left Station A (phone 50 m away, ±10 m, 0 s old), seen 18:48:31, given 42 s later")
    }

    @Test func saysThatIOSGaveAnExitAtOnce() {
        let line = line(.left(regionId: "stop:a"), seenAt: opened)

        #expect(line == """
            iOS: left stop area of Station A (phone 50 m away, ±10 m, 0 s old), seen 18:49:13, given at once
            """)
    }

    @Test func saysWhenIOSGaveNoTimeForAnExit() {
        let line = line(.left(regionId: "arrival:a"), seenAt: nil)

        #expect(line == "iOS: left Station A (phone 50 m away, ±10 m, 0 s old), no time from iOS")
    }

    @Test func givesTheDayOfACrossingSeenOnAnotherDay() {
        let line = line(.left(regionId: "arrival:a"), seenAt: Self.time(23, 50, 0, day: 1))

        #expect(line.hasSuffix(", seen 1 Nov 23:50:00, given 18 h 59 min later"))
    }

    @Test func givesTheFirstStateInsideAStationItsTimeToo() {
        let line = RegionEvent.entered(regionId: "arrival:b").firstStateLine(
            phoneAt: nil, seenAt: Self.time(18, 38, 18), now: opened, catalog: Places.catalog, timeZone: .gmt
        )

        #expect(line == """
            iOS: first state of a new area: inside Station B (iOS gave no position), seen 18:38:18, \
            given 10 min later
            """)
    }

    @Test func readsADateThatNobodySetAsNoTime() {
        #expect(RegionCrossingTime.seen(Date(timeIntervalSinceReferenceDate: 0)) == nil)
        #expect(RegionCrossingTime.seen(.distantPast) == nil)
        #expect(RegionCrossingTime.seen(opened) == opened)
    }

    // MARK: - What iOS holds when the app may be suspended (AC2)

    private func holdLine(
        _ holds: [String: RegionHold], near position: Coordinate? = Places.fiftyMetersFromA, keptAwake: Bool = false
    ) -> String {
        RegionHoldLine.text(
            holds: holds, near: position, keptAwake: keptAwake, now: opened, catalog: Places.catalog, timeZone: .gmt
        )
    }

    @Test func saysThatAnAreaHeldAsInsideWakesNothingOnAWalkBackIn() {
        let line = holdLine([
            "arrival:a": RegionHold(state: .inside, since: Self.time(18, 38, 18)),
            "arrival:b": RegionHold(state: .outside, since: Self.time(18, 30, 0))
        ])

        #expect(line == """
            iOS holds Station A as inside since 18:38:18 (a walk back in wakes nothing); \
            nothing keeps the app awake: iOS can suspend it
            """)
    }

    @Test func saysThatAnAreaHeldAsOutsideIsArmed() {
        let line = holdLine(["arrival:a": RegionHold(state: .outside, since: Self.time(18, 49, 13))], keptAwake: true)

        #expect(line == """
            iOS holds Station A as outside since 18:49:13 (an entry can wake the app); \
            kept awake by the position keeper
            """)
    }

    @Test func saysWhenIOSDoesNotKnowTheStateOfTheArea() {
        let line = holdLine(["arrival:a": RegionHold(state: .unknown, since: nil)])

        #expect(line == """
            iOS holds Station A as unknown, no time from iOS; nothing keeps the app awake: iOS can suspend it
            """)
    }

    @Test func readsTheAreaOfTheStationNearestThePosition() {
        let holds = [
            "arrival:a": RegionHold(state: .inside, since: opened),
            "arrival:b": RegionHold(state: .outside, since: opened),
            "stop:a": RegionHold(state: .inside, since: opened),
            "refresh": RegionHold(state: .inside, since: opened)
        ]

        #expect(holdLine(holds, near: Places.atB).hasPrefix("iOS holds Station B as outside"))
        #expect(holdLine(holds, near: nil).hasPrefix("iOS holds 2 station areas, and the app has no position;"))
        let noStation = holdLine(["refresh": RegionHold(state: .inside, since: opened)])
        #expect(noStation.hasPrefix("iOS holds no station area;"))
    }
}
