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
