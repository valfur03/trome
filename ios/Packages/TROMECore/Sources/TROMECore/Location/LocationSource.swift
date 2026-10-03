public enum LocationSource: Codable, Hashable, Sendable {
    case realGPS
    case fake(FakePosition)
}
