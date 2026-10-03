public enum LocationAuthorization: Sendable {
    case notDetermined
    case denied
    case authorized
}

public enum LocationAccess: Equatable, Sendable {
    case notDecided
    case denied
    case whileUsing
    case always
}

@MainActor
public protocol LocationPermission: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
    func waitForAlwaysQuestion() async
}
