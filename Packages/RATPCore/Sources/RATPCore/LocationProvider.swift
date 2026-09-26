import Foundation

public enum LocationAuthorization: Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
public protocol LocationProvider: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
    func currentCoordinate() async throws -> Coordinate
}
