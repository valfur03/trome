public protocol LocationProvider: Sendable {
    func positions() -> AsyncStream<Coordinate>
}

public struct FakeLocationProvider: LocationProvider {
    public let coordinate: Coordinate

    public init(coordinate: Coordinate) {
        self.coordinate = coordinate
    }

    public func positions() -> AsyncStream<Coordinate> {
        AsyncStream { continuation in
            continuation.yield(coordinate)
        }
    }
}
