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
}

public struct FakeLocationProvider: LocationProvider {
    public let coordinate: Coordinate

    public init(coordinate: Coordinate) {
        self.coordinate = coordinate
    }

    public func events() -> AsyncStream<LocationEvent> {
        AsyncStream { continuation in
            continuation.yield(.position(.exact(coordinate)))
        }
    }
}
