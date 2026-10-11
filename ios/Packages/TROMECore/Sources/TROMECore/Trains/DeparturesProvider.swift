import Foundation

public enum NextTrainsError: Error, Equatable, Sendable {
    case unreachable
    case keyRejected
    case quotaExceeded
    case serviceFailure
    case serverOut(retryAt: Date)
    /// The server of the app refused the app token of this build (`AppTokenRefusal`): only a newer build can
    /// call it again, so the rider is told to update the app, and the app stops asking until it is opened.
    case appTokenRefused
}

public struct DeparturesAnswer: Equatable, Sendable {
    public var departures: [Departure]
    public var answeredAt: Date?
    /// The stops (PRIM monitoring references) whose call failed while another stop of the station answered:
    /// the app does not know the trains of their directions, which is not the same as no train.
    public var unansweredStops: Set<String>

    public init(departures: [Departure], answeredAt: Date? = nil, unansweredStops: Set<String> = []) {
        self.departures = departures
        self.answeredAt = answeredAt
        self.unansweredStops = unansweredStops
    }
}

public protocol DeparturesProvider: Sendable {
    func departures(at stations: [Station]) async throws -> [Departure]
    func departuresAnswer(at stations: [Station]) async throws -> DeparturesAnswer
}

extension DeparturesProvider {
    public func departuresAnswer(at stations: [Station]) async throws -> DeparturesAnswer {
        DeparturesAnswer(departures: try await departures(at: stations))
    }
}
