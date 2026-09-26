public enum LocationAuthorization: Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
public protocol LocationPermission: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
}
