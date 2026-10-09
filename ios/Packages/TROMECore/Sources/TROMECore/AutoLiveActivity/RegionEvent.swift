import Foundation

/// What iOS reports for a watched region: the phone entered it, or left it.
public enum RegionEvent: Equatable, Sendable {
    case entered(regionId: String)
    case left(regionId: String)

    var enteredRegionId: String? {
        guard case .entered(let id) = self else { return nil }
        return id
    }

    /// The station whose stop area the phone left: leaving it ends the arrival there, even with no position.
    var leftStopStationId: String? {
        guard case .left(let id) = self, id.hasPrefix(WatchedRegion.stopPrefix) else { return nil }
        return String(id.dropFirst(WatchedRegion.stopPrefix.count))
    }
}
