import TROMECore
import UserNotifications

/// Asks iOS for notifications, after the location questions. The app sends no notification of its own.
@MainActor
final class UserNotificationPermission: NotificationPermission {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}
