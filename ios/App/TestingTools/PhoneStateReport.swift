#if DEBUG
import CoreLocation
import TROMECore
import UIKit
import UserNotifications

@MainActor
enum PhoneStateReport {
    static func lines(locationSource: LocationSource) async -> [String] {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        return [
            location(CLLocationManager()),
            "Background App Refresh: \(backgroundRefresh(UIApplication.shared.backgroundRefreshStatus))",
            "Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")",
            "Notifications: \(notifications(notificationSettings))",
            "Position: \(position(locationSource))"
        ]
    }

    static func notifications(_ settings: UNNotificationSettings) -> String {
        let authorization = switch settings.authorizationStatus {
        case .authorized: "allowed"
        case .denied: "denied"
        case .notDetermined: "not asked"
        case .provisional: "delivered quietly"
        case .ephemeral: "ephemeral"
        @unknown default: "status \(settings.authorizationStatus.rawValue)"
        }
        var parts = [authorization]
        if settings.alertSetting != .enabled {
            parts.append("no banner")
        }
        if settings.lockScreenSetting != .enabled {
            parts.append("not on the lock screen")
        }
        if settings.scheduledDeliverySetting == .enabled {
            parts.append("in the Scheduled Summary")
        }
        return parts.joined(separator: ", ")
    }

    private static func location(_ manager: CLLocationManager) -> String {
        let authorization = switch manager.authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked"
        @unknown default: "status \(manager.authorizationStatus.rawValue)"
        }
        let accuracy = manager.accuracyAuthorization == .fullAccuracy ? "precise" : "approximate"
        let regions = CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) ? "" : ", no region watch"
        return "Location: \(authorization), \(accuracy)\(regions)"
    }

    private static func backgroundRefresh(_ status: UIBackgroundRefreshStatus) -> String {
        switch status {
        case .available: "on"
        case .denied: "off"
        case .restricted: "restricted"
        @unknown default: "status \(status.rawValue)"
        }
    }

    private static func position(_ source: LocationSource) -> String {
        switch source {
        case .realGPS: "real GPS"
        case .fake(let fakePosition): "fake, \(fakePosition.name)"
        }
    }
}
#endif
