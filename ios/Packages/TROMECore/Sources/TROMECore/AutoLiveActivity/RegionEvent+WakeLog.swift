import Foundation

extension RegionEvent {
    var regionId: String {
        switch self {
        case .entered(let id), .left(let id): id
        }
    }

    /// The line of the Wake log for this event, written when iOS sends it, before the app decides anything:
    /// for a station area it says where the phone was (`WatchedRegion.wakeLabel(ofId:phoneAt:now:catalog:)`),
    /// and when iOS saw the crossing (`RegionCrossingTime`).
    public func wakeLine(
        phoneAt fix: PositionFix?,
        seenAt: Date?,
        now: Date,
        catalog: StationCatalog,
        timeZone: TimeZone = .current
    ) -> String {
        let region = WatchedRegion.wakeLabel(ofId: regionId, phoneAt: fix, now: now, catalog: catalog)
        let what = switch self {
        case .entered: "iOS: entered \(region)"
        case .left: "iOS: left \(region)"
        }
        return what + crossingTime(seenAt: seenAt, now: now, catalog: catalog, timeZone: timeZone)
    }

    /// The line of a first state "inside" a station area, written at once like an entry, and not in the
    /// summary of the first states, which comes only when every new area has answered: a walk reads the time
    /// of the line as the time of the wake, and the decision comes after it. Nil for an area that is not a station.
    public func firstStateLine(
        phoneAt fix: PositionFix?,
        seenAt: Date?,
        now: Date,
        catalog: StationCatalog,
        timeZone: TimeZone = .current
    ) -> String? {
        guard case .entered(let id) = self, WatchedRegion.stationId(inRegionId: id) != nil else { return nil }
        let region = WatchedRegion.wakeLabel(ofId: id, phoneAt: fix, now: now, catalog: catalog)
        return "iOS: first state of a new area: inside \(region)"
            + crossingTime(seenAt: seenAt, now: now, catalog: catalog, timeZone: timeZone)
    }

    /// Only a station area gets the time: the other areas only plan the stations again.
    private func crossingTime(seenAt: Date?, now: Date, catalog: StationCatalog, timeZone: TimeZone) -> String {
        guard WatchedRegion.stationId(inRegionId: regionId).flatMap(catalog.station(withId:)) != nil else { return "" }
        return ", " + RegionCrossingTime.line(seenAt: seenAt, now: now, timeZone: timeZone)
    }
}
