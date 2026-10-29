import Foundation

/// Why the rules ended the Live Activity, for the wake log: the rider can then tell a Live Activity that ended
/// before the next station (so that station notifies) from one that switched.
enum LiveActivityEnding: Equatable, Sendable {
    case farFrom(Station, distanceMeters: Double)
    case maximumDuration(TimeInterval)
    /// The rider reached another station: a Live Activity that the server started cannot switch, as it listens to
    /// the channel of its own station, so it ends, and the new station starts its own.
    case pushedForAnotherStation(arrivedAt: Station)

    var summary: String {
        switch self {
        case .farFrom(let station, let distance):
            "Live Activity ended: \(Int(distance)) m from \(station.name)"
        case .maximumDuration(let duration) where duration < 60:
            "Live Activity ended: \(Int(duration)) s after it started"
        case .maximumDuration(let duration):
            "Live Activity ended: \(Int(duration / 60)) min after it started"
        case .pushedForAnotherStation(let station):
            "Live Activity ended: the server started it for another station than \(station.name)"
        }
    }
}
