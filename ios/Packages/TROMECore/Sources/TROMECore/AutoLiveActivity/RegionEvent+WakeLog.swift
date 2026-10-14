#if DEBUG
import Foundation

extension RegionEvent {
    var regionId: String {
        switch self {
        case .entered(let id), .left(let id): id
        }
    }

    /// The line of the Wake log for this event, written when iOS sends it, before the app decides anything:
    /// for a station area it says where the phone was (`WatchedRegion.wakeLabel(ofId:phoneAt:now:catalog:)`).
    public func wakeLine(phoneAt fix: PositionFix?, now: Date, catalog: StationCatalog) -> String {
        let region = WatchedRegion.wakeLabel(ofId: regionId, phoneAt: fix, now: now, catalog: catalog)
        return switch self {
        case .entered: "iOS: entered \(region)"
        case .left: "iOS: left \(region)"
        }
    }

    /// The line of a first state "inside" a station area, written at once like an entry, and not in the
    /// summary of the first states, which comes only when every new area has answered: a walk reads the time
    /// of the line as the time of the wake, and the decision comes after it. Nil for an area that is not a station.
    public func firstStateLine(phoneAt fix: PositionFix?, now: Date, catalog: StationCatalog) -> String? {
        guard case .entered(let id) = self, WatchedRegion.stationId(inRegionId: id) != nil else { return nil }
        let region = WatchedRegion.wakeLabel(ofId: id, phoneAt: fix, now: now, catalog: catalog)
        return "iOS: first state of a new area: inside \(region)"
    }
}
#endif
