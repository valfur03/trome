public enum LocationProblem: Equatable, Sendable {
    case permissionDenied
    case unavailable
}

public enum LocationEvent: Equatable, Sendable {
    case position(PositionFix)
    case problem(LocationProblem)
}

public protocol LocationProvider: Sendable {
    func events() -> AsyncStream<LocationEvent>
    @MainActor func currentFix() async -> PositionFix?
}
