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
}
#endif
