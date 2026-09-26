import RATPCore
import SwiftUI
import UIKit

struct PermissionsSection: View {
    let permissions: PermissionsModel
    let nearestStationModel: NearestStationModel

    var body: some View {
        Section("Permissions") {
            locationRow
            if let notifications = permissions.notifications {
                notificationsRow(notifications)
            }
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        switch permissions.location {
        case .always:
            PermissionRow(title: "Location", state: "Always", isGranted: true, kind: .location)
        case .whileUsing:
            PermissionRow(
                title: "Location",
                state: "While Using the App",
                isGranted: false,
                kind: .location,
                hint: "The Live Activity can start by itself only while the app is open. "
                    + "To get a notification near a station when the app is closed, set Location to Always.",
                fix: .openSettings
            )
        case .denied:
            PermissionRow(
                title: "Location",
                state: "Off",
                isGranted: false,
                kind: .location,
                hint: "The app cannot find the nearest station without your location. "
                    + "Turn on Location for RATP Activity in Settings, and choose Always.",
                fix: .openSettings
            )
        case .notDecided:
            PermissionRow(
                title: "Location",
                state: "Not asked yet",
                isGranted: false,
                kind: .location,
                hint: "The app needs your location to find the nearest metro or RER station.",
                fix: .action("Allow location") {
                    Task {
                        await nearestStationModel.refresh()
                        await permissions.refresh()
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func notificationsRow(_ notifications: NotificationAccess) -> some View {
        switch notifications {
        case .allowed:
            PermissionRow(title: "Notifications", state: "On", isGranted: true, kind: .notifications)
        case .denied:
            PermissionRow(
                title: "Notifications",
                state: "Off",
                isGranted: false,
                kind: .notifications,
                hint: "The app cannot tell you that you are near a station while it is closed. "
                    + "Turn on Notifications for RATP Activity in Settings.",
                fix: .openSettings
            )
        case .notDecided:
            PermissionRow(
                title: "Notifications",
                state: "Not asked yet",
                isGranted: false,
                kind: .notifications,
                hint: "The app asks for notifications once it can use your location."
            )
        }
    }
}

private struct PermissionRow: View {
    enum Kind: String {
        case location
        case notifications
    }

    enum Fix {
        case openSettings
        case action(String, () -> Void)
    }

    let title: String
    let state: String
    let isGranted: Bool
    let kind: Kind
    var hint: String?
    var fix: Fix?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StateRow(state: state) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isGranted ? .green : .orange)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(kind.rawValue)PermissionStatus")
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(kind.rawValue)PermissionHint")
            }
            fixButton
        }
    }

    @ViewBuilder
    private var fixButton: some View {
        fixButtonContent
            .buttonStyle(.bordered)
            .adaptiveButtonBorderShape()
    }

    @ViewBuilder
    private var fixButtonContent: some View {
        switch fix {
        case .openSettings:
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .accessibilityIdentifier("\(kind.rawValue)SettingsButton")
        case .action(let label, let action):
            Button(label, action: action)
                .accessibilityIdentifier("\(kind.rawValue)FixButton")
        case nil:
            EmptyView()
        }
    }
}
