import Observation
import RATPCore
import UserNotifications

enum NotificationAccess {
    case notDecided
    case denied
    case allowed
}

@MainActor
@Observable
final class PermissionsModel {
    private(set) var location: LocationAccess
    private(set) var notifications: NotificationAccess?

    private let locationPermission: CoreLocationPermission

    init(locationPermission: CoreLocationPermission) {
        self.locationPermission = locationPermission
        location = locationPermission.access
        locationPermission.onAccessChange = { [weak self] in
            guard let self else { return }
            location = self.locationPermission.access
        }
    }

    func refresh() async {
        location = locationPermission.access
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = switch settings.authorizationStatus {
        case .notDetermined: .notDecided
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        @unknown default: .denied
        }
    }
}
