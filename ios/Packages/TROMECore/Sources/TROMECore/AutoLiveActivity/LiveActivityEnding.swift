import Foundation

/// Why the rules ended the Live Activity, for the wake log: the rider can then tell a Live Activity that ended
/// before the next station (so that station notifies) from one that switched.
enum LiveActivityEnding: Equatable, Sendable {
    case farFrom(Station, distanceMeters: Double)
    case maximumDuration(TimeInterval)

    var summary: String {
        switch self {
        case .farFrom(let station, let distance):
            "Live Activity ended: \(Int(distance)) m from \(station.name)"
        case .maximumDuration(let duration) where duration < 60:
            "Live Activity ended: \(Int(duration)) s after it started"
        case .maximumDuration(let duration):
            "Live Activity ended: \(Int(duration / 60)) min after it started"
        }
    }
}
