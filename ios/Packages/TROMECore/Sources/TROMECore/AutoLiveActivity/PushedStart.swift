import Foundation

/// A start of the Live Activity that the server took ("started" or "already-started"), until the app follows the
/// Live Activity that Apple's push brings. The app then adopts it as the one it shows, so that the rules end it at
/// 250 meters or after 45 minutes, and the next station does not start a second one.
public struct PushedStart: Codable, Equatable, Sendable {
    /// How long a rider who opens the app at the station waits for the push before the app starts the Live Activity
    /// itself. Apple's push usually lands within seconds; a start of the app's own before it would be a second one.
    static let landingWait: TimeInterval = 30

    public var stationId: String
    public var answeredAt: Date

    public init(stationId: String, answeredAt: Date) {
        self.stationId = stationId
        self.answeredAt = answeredAt
    }

    func awaitsItsLiveActivity(at stationId: String, now: Date) -> Bool {
        stationId == self.stationId && now.timeIntervalSince(answeredAt) < Self.landingWait
    }
}

extension AutoLiveActivityRules {
    /// A Live Activity shows that the app did not start: with a start that the server took, it is the one that the
    /// push brought. It is followed from the server's answer, so that the 45 minutes count from the start, also
    /// when the app sees it later; the rider was within 150 meters of the station at the ask.
    func adoptThePushedLiveActivity(state: AutoLiveActivityState) -> AutoLiveActivityState? {
        guard state.shown == nil, state.exampleStartedAt == nil, let pushed = state.pushedStart else { return nil }
        var adopted = state
        adopted.shown = .init(
            stationId: pushed.stationId, startedAt: pushed.answeredAt, hasBeenNear: true, isStartedByThePush: true
        )
        return adopted
    }
}
