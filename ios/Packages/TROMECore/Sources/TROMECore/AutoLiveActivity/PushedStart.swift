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
    /// Whether the phone was within 250 meters of the station at the ask: always at an arrival. A test of the start
    /// asks from anywhere, so its Live Activity ends by distance only once the phone has been near the station, as
    /// one started by hand: a test at a desk then shows it, and the 45 minutes end it.
    var hasBeenNear = true

    init(stationId: String, answeredAt: Date, hasBeenNear: Bool = true) {
        self.stationId = stationId
        self.answeredAt = answeredAt
        self.hasBeenNear = hasBeenNear
    }

    /// A state kept by a build before the test of the start has no `hasBeenNear`: its start was an arrival.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationId = try container.decode(String.self, forKey: .stationId)
        answeredAt = try container.decode(Date.self, forKey: .answeredAt)
        hasBeenNear = try container.decodeIfPresent(Bool.self, forKey: .hasBeenNear) ?? true
    }

    func awaitsItsLiveActivity(at stationId: String, now: Date) -> Bool {
        stationId == self.stationId && now.timeIntervalSince(answeredAt) < Self.landingWait
    }
}
