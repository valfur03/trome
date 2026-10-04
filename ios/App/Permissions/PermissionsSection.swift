import TROMECore
import SwiftUI
import UIKit

struct PermissionsSection: View {
    let permissions: PermissionsModel
    let nearestStationModel: NearestStationModel

    @Environment(\.appName) private var appName

    var body: some View {
        let rows = [locationRow] + (permissions.notifications.map { [notificationsRow($0)] } ?? [])
        NightCard(isProblem: rows.contains { !$0.isGranted }) {
            Overline(title: "Permissions")
            ForEach(rows.indices, id: \.self) { index in
                if index > 0 {
                    NightDivider()
                }
                rows[index]
            }
        }
    }

    private var locationRow: PermissionRow {
        switch permissions.location {
        case .always:
            PermissionRow(
                title: "Location",
                state: "Always",
                isGranted: true,
                kind: .location,
                hint: """
                    While the Live Activity shows, your iPhone may show that the app uses your location \
                    to keep the train times up to date, and this is normal.
                    """
            )
        case .whileUsing:
            PermissionRow(
                title: "Location",
                state: "While Using the App",
                isGranted: false,
                kind: .location,
                hint: """
                    The Live Activity can start by itself only while the app is open. \
                    To get a notification near a station when the app is closed, set Location to Always. \
                    While the Live Activity shows, your iPhone may show that the app uses your location \
                    to keep the train times up to date, and this is normal.
                    """,
                fix: .openSettings
            )
        case .denied:
            PermissionRow(
                title: "Location",
                state: "Off",
                isGranted: false,
                kind: .location,
                hint: """
                    The app cannot find the nearest station without your location. \
                    Turn on Location for \(appName) in Settings, and choose Always.
                    """,
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

    private func notificationsRow(_ notifications: NotificationAccess) -> PermissionRow {
        switch notifications {
        case .allowed:
            PermissionRow(title: "Notifications", state: "On", isGranted: true, kind: .notifications)
        case .denied:
            PermissionRow(
                title: "Notifications",
                state: "Off",
                isGranted: false,
                kind: .notifications,
                hint: """
                    The app cannot tell you that you are near a station while it is closed. \
                    Turn on Notifications for \(appName) in Settings.
                    """,
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
        case action(LocalizedStringKey, () -> Void)
    }

    let title: LocalizedStringKey
    let state: LocalizedStringKey
    let isGranted: Bool
    let kind: Kind
    var hint: LocalizedStringKey?
    var fix: Fix?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StateRow(state: state, kind: isGranted ? .fine : .problem) {
                Text(title)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(kind.rawValue)PermissionStatus")
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(NightLook.secondaryText)
                    .accessibilityIdentifier("\(kind.rawValue)PermissionHint")
            }
            fixButton
                .buttonStyle(.problem)
        }
    }

    @ViewBuilder
    private var fixButton: some View {
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
