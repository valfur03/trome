import Foundation

/// What iOS holds for an area that it watches for the app: its last state, and since when.
/// iOS wakes the app only when the state changes, so an area held as inside wakes nothing on a walk back in.
public struct RegionHold: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case inside
        case outside
        case unknown
        case notWatched = "not watched"
    }

    public var state: State
    /// Nil when iOS gave no time (`RegionCrossingTime.seen(_:)`).
    public var since: Date?

    public init(state: State, since: Date?) {
        self.state = state
        self.since = since
    }
}

/// The Wake log line, written when the app goes to the background and when the app stops keeping itself awake (the
/// end of a Live Activity, of a second chance or of a silent start), that says what iOS holds for the area of the
/// nearest station and whether anything keeps the app awake. A later silence then reads as "suspended, area outside,
/// armed", or "area still held as inside": a walk back into it is no fair test of a wake.
/// The bound: the line is written only when its text differs from the newest line of its kind, so a rider who opens
/// and leaves the app many times with nothing changed adds one line; and the log keeps only the `maximumLines` newest.
enum RegionHoldLine {
    static let prefix = "iOS holds "
    static let maximumLines = 30

    static func isHoldLine(_ entry: WakeLogEntry) -> Bool {
        entry.kind == .system && entry.text.hasPrefix(prefix)
    }

    static func text(
        holds: [String: RegionHold],
        near position: Coordinate?,
        keptAwake: Bool,
        now: Date,
        catalog: StationCatalog,
        timeZone: TimeZone = .current
    ) -> String {
        let awake = keptAwake ? "kept awake by the position keeper" : "nothing keeps the app awake: iOS can suspend it"
        return "\(prefix)\(area(holds, near: position, now: now, catalog: catalog, timeZone: timeZone)); \(awake)"
    }

    private static func area(
        _ holds: [String: RegionHold], near position: Coordinate?, now: Date, catalog: StationCatalog,
        timeZone: TimeZone
    ) -> String {
        let stations = holds.compactMap { id, hold in
            WatchedRegion.arrivalStationId(inRegionId: id).flatMap(catalog.station(withId:))
                .map { (station: $0, hold: hold) }
        }
        guard !stations.isEmpty else { return "no station area" }
        guard let position else { return "\(stations.count) station areas, and the app has no position" }
        guard let nearest = stations.min(by: {
            position.distance(to: $0.station.coordinate) < position.distance(to: $1.station.coordinate)
        }) else { return "no station area" }
        let hold = nearest.hold
        let since = hold.since.map { " since \(WakeLogClock(timeZone: timeZone).time($0, now: now))" }
            ?? ", no time from iOS"
        return "\(nearest.station.name) as \(hold.state.rawValue)\(since)\(meaning(of: hold.state))"
    }

    private static func meaning(of state: RegionHold.State) -> String {
        switch state {
        case .inside: " (a walk back in wakes nothing)"
        case .outside: " (an entry can wake the app)"
        case .unknown, .notWatched: ""
        }
    }
}
