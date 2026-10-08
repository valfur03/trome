import Foundation

public enum NextTrainsError: Error, Equatable, Sendable {
    case unreachable
    case keyRejected
    case quotaExceeded
    case serviceFailure
    case serverOut(retryAt: Date)
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
