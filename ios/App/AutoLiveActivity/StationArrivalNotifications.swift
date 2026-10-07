import TROMECore
import UserNotifications

@MainActor
final class UserNotificationArrivalNotifier: ArrivalNotifier {
    nonisolated static let identifier = "stationArrival"
    nonisolated static let stationIdKey = "stationId"
    nonisolated static let categoryIdentifier = "stationArrival"

    private let center = UNUserNotificationCenter.current()

    nonisolated static func registerActions(in center: UNUserNotificationCenter) {
        let actions = ArrivalNotificationAction.allCases.map {
            UNNotificationAction(identifier: $0.rawValue, title: title(of: $0), options: [])
        }
        let category = UNNotificationCategory(
            identifier: categoryIdentifier, actions: actions, intentIdentifiers: [], options: []
        )
        center.setNotificationCategories([category])
    }

    nonisolated private static func title(of action: ArrivalNotificationAction) -> String {
        switch action {
        case .notForOneHour:
            String(localized: "Not for 1 h")
        case .notToday:
            String(localized: "Not today")
        }
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notify(_ station: Station) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Next trains at \(station.name)")
        content.sound = .default
        content.userInfo = [Self.stationIdKey: station.id]
        content.categoryIdentifier = Self.categoryIdentifier
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    func withdraw() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

final class ArrivalNotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate {
    private let onTap: @MainActor @Sendable (String) async -> Void
    private let onAction: @MainActor @Sendable (ArrivalNotificationAction) async -> Void

    init(
        onTap: @escaping @MainActor @Sendable (String) async -> Void,
        onAction: @escaping @MainActor @Sendable (ArrivalNotificationAction) async -> Void
    ) {
        self.onTap = onTap
        self.onAction = onAction
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
        let action = ArrivalNotificationAction(rawValue: response.actionIdentifier)
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor [onTap, onAction] in
            if let stationId {
                await onTap(stationId)
            } else if let action {
                await onAction(action)
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
