import Foundation

/// A start of the Live Activity that the server took ("started" or "already-started"), until the app follows the
/// Live Activity that Apple's push brings. The app then adopts it as the one it shows, so that the rules end it at
/// 250 meters or after 45 minutes, and the next station does not start a second one.
struct PushedStart: Codable, Equatable, Sendable {
    /// How long a rider who opens the app at the station waits for the push before the app starts the Live Activity
    /// itself. Apple's push usually lands within seconds; a start of the app's own before it would be a second one.
    static let landingWait: TimeInterval = 30

    var stationId: String
    var answeredAt: Date

    func awaitsItsLiveActivity(at stationId: String, now: Date) -> Bool {
        stationId == self.stationId && now.timeIntervalSince(answeredAt) < Self.landingWait
    }
}
