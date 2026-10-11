import Foundation

/// iOS reports that the phone entered the 150 m area of a station.
/// iOS also says so when it is wrong: after a phone ran out of battery and started again, it reported 21 stations
/// across Paris in 25 seconds, with no position, while the phone was 378 m from the nearest one.
/// So a report alone is no arrival: a position that the app trusts must agree with it.
enum ReportedArrivalRules {
    /// How long the app waits for the position that it asks iOS for, about the time that iOS takes to answer.
    static let maximumWait: Duration = .seconds(10)

    /// The position to decide the report on, or nil when no trusted position agrees with it.
    /// A trusted position within the stop area, but outside the 150 m, may lag a few seconds behind iOS:
    /// the app then takes the phone at the station.
    static func position(confirming station: Station, with fix: PositionFix?, now: Date) -> PositionFix? {
        guard let fix, isTrusted(fix, now: now) else { return nil }
        let distance = fix.coordinate.distance(to: station.coordinate)
        if distance <= AutoLiveActivityRules.arrivalRadiusMeters {
            return fix
        }
        guard distance <= AutoLiveActivityRules.stopRadiusMeters else { return nil }
        return PositionFix(coordinate: station.coordinate, accuracyMeters: 0, timestamp: now)
    }

    /// A trusted position of the last 15 seconds settles a report: the app asks iOS for no new one.
    static func settles(_ fix: PositionFix?, now: Date) -> Bool {
        fix.map { AutoLiveActivityRules.trusts($0, now: now) } ?? false
    }

    /// A refusal is final when a trusted position of the last 15 seconds puts the phone far from the station.
    /// With no such position, the phone may still be there, or have come since: the app gives the report
    /// a second chance (`ArrivalSecondChance`).
    static func isFinal(refusalWith fix: PositionFix?, now: Date) -> Bool {
        settles(fix, now: now)
    }

    /// The line of the wake log that says why a report is not an arrival.
    static func refusal(at station: Station, position fix: PositionFix?, now: Date) -> String {
        "No arrival at \(station.name): \(reason(at: station, position: fix, now: now))"
    }

    static func reason(at station: Station, position fix: PositionFix?, now: Date) -> String {
        if let fix, isTrusted(fix, now: now) {
            return "the position is \(Int(fix.coordinate.distance(to: station.coordinate))) m away"
        }
        if let fix {
            let age = Int(now.timeIntervalSince(fix.timestamp))
            return "the position is ±\(Int(fix.accuracyMeters)) m and \(age) s old"
        }
        return "iOS gave no position"
    }

    private static func isTrusted(_ fix: PositionFix, now: Date) -> Bool {
        AutoLiveActivityRules.trusts(fix, now: now, maximumAge: AutoLiveActivityRules.maximumMonitoredPositionAge)
    }
}
