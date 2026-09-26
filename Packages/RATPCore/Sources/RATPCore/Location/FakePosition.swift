public struct FakePosition: Codable, Hashable, Sendable {
    public let name: String
    public let coordinate: Coordinate

    public init(name: String, coordinate: Coordinate) {
        self.name = name
        self.coordinate = coordinate
    }
}

public enum LocationSource: Codable, Hashable, Sendable {
    case realGPS
    case fake(FakePosition)
}
