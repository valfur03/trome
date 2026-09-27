import RATPCore
import UserNotifications

@MainActor
final class UserNotificationArrivalNotifier: ArrivalNotifier {
    nonisolated static let identifier = "stationArrival"
    nonisolated static let stationIdKey = "stationId"

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notify(_ station: Station) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Next trains at \(station.name)")
        content.body = String(localized: "Tap to show them on your lock screen.")
        content.sound = .default
        content.userInfo = [Self.stationIdKey: station.id]
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    func withdraw() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

final class ArrivalNotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {
    private let onTap: @MainActor @Sendable (String) async -> Void

    init(onTap: @escaping @MainActor @Sendable (String) async -> Void) {
        self.onTap = onTap
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let stationId = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? userInfo[UserNotificationArrivalNotifier.stationIdKey] as? String
            : nil
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor [onTap] in
            if let stationId {
                await onTap(stationId)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
