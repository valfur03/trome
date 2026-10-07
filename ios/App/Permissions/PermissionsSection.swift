import TROMECore
import SwiftUI
import UIKit

struct PermissionsSection: View {
    let permissions: PermissionsModel
    let nearestStationModel: NearestStationModel

    var body: some View {
        let rows = [locationRow] + (permissions.notifications.map { [notificationsRow($0)] } ?? [])
        NightCard(isProblem: rows.contains { !$0.isGranted }) {
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
            PermissionRow(title: "Location", state: "Always", isGranted: true, kind: .location)
        case .whileUsing:
            PermissionRow(
                title: "Location",
                state: "While Using the App",
                isGranted: false,
                kind: .location,
                hint: "Choose Always",
                fix: .openSettings
            )
        case .denied:
            PermissionRow(
                title: "Location",
                state: "Off",
                isGranted: false,
                kind: .location,
                hint: "Choose Always",
                fix: .openSettings
            )
        case .notDecided:
            PermissionRow(
                title: "Location",
                state: "Not asked yet",
                isGranted: false,
                kind: .location,
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
                fix: .openSettings
            )
        case .notDecided:
            PermissionRow(title: "Notifications", state: "Not asked yet", isGranted: false, kind: .notifications)
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
