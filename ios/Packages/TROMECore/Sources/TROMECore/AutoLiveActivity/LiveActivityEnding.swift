import Foundation

/// Why a Live Activity ended, for the wake log: one line per end, which says who ended it (the app's rules, the
/// rider, or iOS). The rider can then tell a Live Activity that ended before the next station (so that station
/// starts its own, in the background through the server) from one that switched, or that was still on screen.
enum LiveActivityEnding: Equatable, Sendable {
    case farFrom(Station, distanceMeters: Double)
    case maximumDuration(TimeInterval)
    /// The rider reached another station: a Live Activity that the server started cannot switch, as it listens to
    /// the channel of its own station, so it ends, and the new station starts its own.
    case pushedForAnotherStation(arrivedAt: Station)
    case stoppedByHand
    case snoozed(SnoozeDuration)
    case automaticStartTurnedOff
    /// The app found the Live Activity gone, with no end of its own: the rider or iOS removed it.
    case outsideTheApp(OutsideEnd, iOSState: LiveActivityEndState?)

    enum OutsideEnd: Equatable, Sendable {
        case liveActivitiesTurnedOff
        case systemLimit
        case swipedAway
        case endedByIOS
        case noReason
    }

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
        case .stoppedByHand:
            "Live Activity ended by the rider: stopped by hand"
        case .snoozed(let duration):
            "Live Activity ended by the rider: snoozed \(Self.text(of: duration))"
        case .automaticStartTurnedOff:
            "Live Activity ended by the rider: automatic start turned off"
        case .outsideTheApp(let end, let state):
            Self.text(of: end) + (state.map { " (iOS: \($0.rawValue))" } ?? "")
        }
    }

    private static func text(of duration: SnoozeDuration) -> String {
        switch duration {
        case .thirtyMinutes: "for 30 min"
        case .oneHour: "for 1 h"
        case .restOfToday: "for the rest of the day"
        }
    }

    private static func text(of end: OutsideEnd) -> String {
        switch end {
        case .liveActivitiesTurnedOff:
            "Live Activity ended by iOS: Live Activities are off in Settings"
        case .systemLimit:
            "Live Activity ended by iOS: \(Int(AutoLiveActivityRules.systemMaximumDuration / 3_600)) h limit"
        case .swipedAway:
            "Live Activity ended by the rider: swiped away"
        case .endedByIOS:
            "Live Activity ended by iOS"
        case .noReason:
            "Live Activity ended outside the app: iOS gave no reason"
        }
    }
}
