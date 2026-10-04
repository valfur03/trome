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

    public init(departures: [Departure], answeredAt: Date? = nil) {
        self.departures = departures
        self.answeredAt = answeredAt
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
