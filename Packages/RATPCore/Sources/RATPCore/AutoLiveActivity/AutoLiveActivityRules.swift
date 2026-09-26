import Foundation

public struct AutoLiveActivityState: Codable, Equatable, Sendable {
    public struct Shown: Codable, Equatable, Sendable {
        public var stationId: String
        public var startedAt: Date
        public var hasBeenNear: Bool

        public init(stationId: String, startedAt: Date, hasBeenNear: Bool) {
            self.stationId = stationId
            self.startedAt = startedAt
            self.hasBeenNear = hasBeenNear
        }
    }

    public var arrivalStationId: String?
    public var shown: Shown?

    public init(arrivalStationId: String? = nil, shown: Shown? = nil) {
        self.arrivalStationId = arrivalStationId
        self.shown = shown
    }
}

public struct AutoLiveActivityRules: Sendable {
    public static let arrivalRadiusMeters = 150.0
    public static let stopRadiusMeters = 250.0
    public static let defaultMaximumDuration: TimeInterval = 45 * 60

    public enum Action: Equatable, Sendable {
        case notify(Station)
        case start(Station)
        case switchTo(Station)
        case end
        case withdrawNotification
    }

    public struct Decision: Equatable, Sendable {
        public var state: AutoLiveActivityState
        public var actions: [Action]
    }

    public let maximumDuration: TimeInterval

    public init(maximumDuration: TimeInterval = Self.defaultMaximumDuration) {
        self.maximumDuration = maximumDuration
    }

    public func decide(
        state: AutoLiveActivityState,
        position: Coordinate?,
        now: Date,
        appIsActive: Bool,
        catalog: StationCatalog
    ) -> Decision {
        var decision = Decision(state: state, actions: [])
        if let shown = state.shown, now.timeIntervalSince(shown.startedAt) >= maximumDuration {
            decision.end()
        }
        guard let position else { return decision }
        decision.detectArrival(at: position, now: now, appIsActive: appIsActive, catalog: catalog)
        decision.checkDistanceToShownStation(from: position, catalog: catalog)
        return decision
    }
}

private extension AutoLiveActivityRules.Decision {
    mutating func end() {
        state.shown = nil
        actions.append(.end)
    }

    mutating func detectArrival(at position: Coordinate, now: Date, appIsActive: Bool, catalog: StationCatalog) {
        let nearest = catalog.nearestStation(to: position, within: AutoLiveActivityRules.arrivalRadiusMeters)?.station
        if let nearest, nearest.id != state.arrivalStationId {
            state.arrivalStationId = nearest.id
            arrive(at: nearest, now: now, appIsActive: appIsActive)
        } else if nearest == nil, let arrivalId = state.arrivalStationId,
                  let arrival = catalog.station(withId: arrivalId),
                  position.distance(to: arrival.coordinate) > AutoLiveActivityRules.stopRadiusMeters {
            state.arrivalStationId = nil
            actions.append(.withdrawNotification)
        }
    }

    mutating func arrive(at station: Station, now: Date, appIsActive: Bool) {
        if let shown = state.shown {
            guard shown.stationId != station.id else { return }
            state.shown = .init(stationId: station.id, startedAt: shown.startedAt, hasBeenNear: true)
            actions.append(.switchTo(station))
        } else if appIsActive {
            state.shown = .init(stationId: station.id, startedAt: now, hasBeenNear: true)
            actions.append(.start(station))
        } else {
            actions.append(.notify(station))
        }
    }

    mutating func checkDistanceToShownStation(from position: Coordinate, catalog: StationCatalog) {
        guard let shown = state.shown, let station = catalog.station(withId: shown.stationId) else { return }
        if position.distance(to: station.coordinate) <= AutoLiveActivityRules.stopRadiusMeters {
            state.shown?.hasBeenNear = true
        } else if shown.hasBeenNear {
            end()
        }
    }
}
