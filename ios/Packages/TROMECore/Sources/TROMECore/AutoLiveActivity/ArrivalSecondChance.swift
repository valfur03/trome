import Foundation

/// A report of arrival that the app refused for lack of a trusted position, not because a position was far.
/// At a real station, the first position after the wake is often rough (cell towers only, a street between tall
/// buildings), and iOS reports the area again only after the phone has left it.
/// So the app asks iOS again for a while, and decides as soon as a trusted position comes.
struct ArrivalSecondChance: Equatable {
    /// Two minutes after the report of iOS, plus the last ask.
    /// A rider walks across the 150 m area in about that time, and is then often underground, with no GPS;
    /// it also gives a GPS that starts cold several tries to get its first fix.
    static let limit: TimeInterval = 120
    /// The wait between two asks, so that a phone that answers at once with a rough position is not asked nonstop.
    static let interval: Duration = .seconds(5)

    enum Verdict: Equatable {
        /// A trusted position within 150 m: the arrival rules decide on it.
        case atTheStation
        case far(meters: Int)
        case undecided
    }

    enum End {
        case outcome(ArrivalOutcome)
        case far(meters: Int)
        case left
        case limit(lastPosition: PositionFix?)
        case fakePosition
        case automaticStartOff
    }

    let station: Station
    let reportedAt: Date
    /// A trusted position put the phone within 150 m, and the arrival rules are deciding on it.
    var isBeingDecided = false

    /// Only a trusted position within the 150 m of the station counts: a second chance never notifies for a station
    /// that no trusted position puts the rider at. A trusted position beyond the 250 m ends it.
    func verdict(on fix: PositionFix?, now: Date) -> Verdict {
        guard let fix, AutoLiveActivityRules.trusts(fix, now: now) else { return .undecided }
        let distance = fix.coordinate.distance(to: station.coordinate)
        if distance <= AutoLiveActivityRules.arrivalRadiusMeters {
            return .atTheStation
        }
        if distance > AutoLiveActivityRules.stopRadiusMeters {
            return .far(meters: Int(distance))
        }
        return .undecided
    }

    func isOver(now: Date) -> Bool {
        now.timeIntervalSince(reportedAt) >= Self.limit
    }

    var startLine: String {
        "Second chance at \(station.name): asks iOS for a position for up to \(Int(Self.limit)) s"
    }

    func line(for end: End, now: Date) -> String {
        let after = "after \(Int(now.timeIntervalSince(reportedAt))) s"
        let result = switch end {
        case .outcome(.notified(station)): "notified \(after)"
        case .outcome(.started(station)): "Live Activity started \(after)"
        case .outcome(let outcome): "ended \(after): \(outcome.summary)"
        case .far(let meters): "gave up \(after): the position is \(meters) m away"
        case .left: "gave up \(after): iOS says the phone left its area"
        case .limit(let fix): "gave up \(after): \(ReportedArrivalRules.reason(at: station, position: fix, now: now))"
        case .fakePosition: "gave up \(after): a fake position is on"
        case .automaticStartOff: "gave up \(after): the automatic start is snoozed or off"
        }
        return "Second chance at \(station.name): \(result)"
    }
}
