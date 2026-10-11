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

    private enum CodingKeys: String, CodingKey {
        case arrivalStationId
        case shown
        case pause
        case openArrivalStationId
        case exampleStartedAt
    }

    public var arrivalStationId: String?
    public var shown: Shown? {
        didSet {
            if shown != nil {
                openArrivalStationId = nil
                exampleStartedAt = nil
            }
        }
    }
    public var pendingArrivalStationId: String?
    public var pause: StationPause?
    var openArrivalStationId: String?
    public var exampleStartedAt: Date?

    public init(
        arrivalStationId: String? = nil,
        shown: Shown? = nil,
        pendingArrivalStationId: String? = nil,
        pause: StationPause? = nil
    ) {
        self.arrivalStationId = arrivalStationId
        self.shown = shown
        self.pendingArrivalStationId = pendingArrivalStationId
        self.pause = pause
    }
}

public struct AutoLiveActivityRules: Sendable {
    public static let arrivalRadiusMeters = 150.0
    public static let stopRadiusMeters = 250.0
    public static let defaultMaximumDuration: TimeInterval = 45 * 60
    static let systemMaximumDuration: TimeInterval = 8 * 60 * 60
    static let maximumAccuracyMeters = 100.0
    static let maximumPositionAge: TimeInterval = 15
    static let maximumMonitoredPositionAge: TimeInterval = 120

    public enum ArrivalResponse: Equatable, Sendable {
        case start
        case keepOpen
        case notify
        case later
        case none

        public init(appPhase: AppPhase, allowsAutomaticStart: Bool, activitiesAreEnabled: Bool = true) {
            guard allowsAutomaticStart else {
                self = .none
                return
            }
            switch appPhase {
            case .active: self = activitiesAreEnabled ? .start : .keepOpen
            case .inactive: self = .later
            case .background: self = .notify
            }
        }
    }

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
        var arrival: ArrivalOutcome?
        var ending: LiveActivityEnding?
    }

    public let maximumDuration: TimeInterval
    public let exampleDuration: TimeInterval

    public init(
        maximumDuration: TimeInterval = Self.defaultMaximumDuration,
        exampleDuration: TimeInterval = Self.defaultExampleDuration
    ) {
        self.maximumDuration = maximumDuration
        self.exampleDuration = exampleDuration
    }

    static func trusts(
        _ fix: PositionFix,
        now: Date,
        maximumAge: TimeInterval = maximumPositionAge
    ) -> Bool {
        let isRecent = abs(now.timeIntervalSince(fix.timestamp)) <= maximumAge
        return isPrecise(fix) && isRecent
    }

    static func isPrecise(_ fix: PositionFix) -> Bool {
        (0...maximumAccuracyMeters).contains(fix.accuracyMeters)
    }

    enum RemovalOutcome: Equatable, Sendable {
        case pause(StationPause)
        case endedByTheApp
        case noShownLiveActivity
        case liveActivitiesTurnedOff
        case olderThanTheSystemLimit
    }

    func outcome(
        of removal: LiveActivityRemoval,
        shown: AutoLiveActivityState.Shown?,
        now: Date
    ) -> RemovalOutcome {
        guard !removal.endedByTheApp else { return .endedByTheApp }
        guard let shown else { return .noShownLiveActivity }
        guard removal.activitiesAreEnabled else { return .liveActivitiesTurnedOff }
        guard now.timeIntervalSince(shown.startedAt) < Self.systemMaximumDuration else {
            return .olderThanTheSystemLimit
        }
        return .pause(StationPause(stationId: shown.stationId, end: now.addingTimeInterval(StationPause.duration)))
    }

    func waitsForAResume(state: AutoLiveActivityState, now: Date, onArrival response: ArrivalResponse) -> Bool {
        guard response == .start, state.shown == nil, let stationId = state.openArrivalStationId else { return false }
        return state.pause?.pauses(stationId, at: now) != true
    }

    public func decide(
        state: AutoLiveActivityState,
        position: Coordinate?,
        now: Date,
        onArrival response: ArrivalResponse,
        catalog: StationCatalog
    ) -> Decision {
        var decision = Decision(state: state, actions: [])
        if let shown = state.shown, now.timeIntervalSince(shown.startedAt) >= maximumDuration {
            decision.end(because: .maximumDuration(maximumDuration))
        }
        if let position {
            decision.detectArrival(at: position, now: now, response: response, catalog: catalog)
            decision.checkDistanceToShownStation(from: position, catalog: catalog)
            if waitsForAResume(state: decision.state, now: now, onArrival: response) {
                decision.answerOpenArrival(at: position, now: now, catalog: catalog)
            }
        }
        decision.answerPendingArrival(now: now, response: response, catalog: catalog)
        return decision
    }
}

extension AutoLiveActivityRules.Decision {
    mutating func forgetArrival() {
        state.arrivalStationId = nil
        state.pendingArrivalStationId = nil
        state.openArrivalStationId = nil
        actions.append(.withdrawNotification)
    }
}

private extension AutoLiveActivityRules.Decision {
    mutating func end(because ending: LiveActivityEnding) {
        state.shown = nil
        actions.append(.end)
        self.ending = ending
    }

    mutating func detectArrival(
        at position: Coordinate,
        now: Date,
        response: AutoLiveActivityRules.ArrivalResponse,
        catalog: StationCatalog
    ) {
        guard let nearest = catalog.nearestStation(
            to: position, within: AutoLiveActivityRules.arrivalRadiusMeters
        )?.station else {
            arrival = .noStationNear(catalog.nearestStation(to: position, within: .infinity))
            leaveArrivalIfFar(from: position, catalog: catalog)
            return
        }
        guard nearest.id != state.arrivalStationId else {
            arrival = state.shown?.stationId == nearest.id ? .alreadyShown(nearest) : .alreadyArrived(nearest)
            return
        }
        state.arrivalStationId = nearest.id
        state.pendingArrivalStationId = nil
        state.openArrivalStationId = nil
        arrive(at: nearest, now: now, response: response)
    }

    mutating func leaveArrivalIfFar(from position: Coordinate, catalog: StationCatalog) {
        guard let arrivalId = state.arrivalStationId ?? state.pendingArrivalStationId,
              let arrivalStation = catalog.station(withId: arrivalId),
              position.distance(to: arrivalStation.coordinate) > AutoLiveActivityRules.stopRadiusMeters else { return }
        forgetArrival()
    }

    mutating func arrive(at station: Station, now: Date, response: AutoLiveActivityRules.ArrivalResponse) {
        if let pause = state.pause, pause.pauses(station.id, at: now) {
            arrival = .paused(station, until: pause.end)
            return
        }
        if let shown = state.shown {
            guard shown.stationId != station.id else {
                arrival = .alreadyShown(station)
                return
            }
            state.shown = .init(stationId: station.id, startedAt: shown.startedAt, hasBeenNear: true)
            actions.append(.switchTo(station))
            arrival = .switched(station)
            return
        }
        switch response {
        case .start:
            state.shown = .init(stationId: station.id, startedAt: now, hasBeenNear: true)
            actions.append(.start(station))
            arrival = .started(station)
        case .keepOpen:
            state.openArrivalStationId = station.id
            arrival = .liveActivitiesOff(station)
        case .notify:
            state.openArrivalStationId = station.id
            actions.append(.notify(station))
            arrival = .notified(station)
        case .later:
            state.arrivalStationId = nil
            state.pendingArrivalStationId = station.id
            arrival = .waitsForTheApp(station)
        case .none:
            arrival = .automaticStartOff(station)
        }
    }

    mutating func answerOpenArrival(at position: Coordinate, now: Date, catalog: StationCatalog) {
        guard let stationId = state.openArrivalStationId, let station = catalog.station(withId: stationId),
              position.distance(to: station.coordinate) <= AutoLiveActivityRules.arrivalRadiusMeters else { return }
        state.shown = .init(stationId: station.id, startedAt: now, hasBeenNear: true)
        actions.append(.start(station))
        actions.append(.withdrawNotification)
        arrival = .started(station)
    }

    mutating func answerPendingArrival(
        now: Date,
        response: AutoLiveActivityRules.ArrivalResponse,
        catalog: StationCatalog
    ) {
        guard response != .later, let stationId = state.pendingArrivalStationId else { return }
        state.pendingArrivalStationId = nil
        guard let station = catalog.station(withId: stationId) else { return }
        state.arrivalStationId = station.id
        arrive(at: station, now: now, response: response)
    }

    mutating func checkDistanceToShownStation(from position: Coordinate, catalog: StationCatalog) {
        guard let shown = state.shown, let station = catalog.station(withId: shown.stationId) else { return }
        let distance = position.distance(to: station.coordinate)
        if distance <= AutoLiveActivityRules.stopRadiusMeters {
            state.shown?.hasBeenNear = true
        } else if shown.hasBeenNear {
            end(because: .farFrom(station, distanceMeters: distance))
        }
    }
}
