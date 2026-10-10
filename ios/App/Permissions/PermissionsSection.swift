import TROMECore
import SwiftUI
import UIKit

struct PermissionsSection: View {
    let permissions: PermissionsModel
    let nearestStationModel: NearestStationModel

    var body: some View {
        let rows = [locationRow] + (permissions.notifications.map { [notificationsRow($0)] } ?? [])
        NightCard(isProblem: rows.contains { $0.status == .needsAction }) {
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
            PermissionRow(title: "Location", state: "Always", status: .granted, kind: .location)
        case .whileUsing:
            PermissionRow(
                title: "Location",
                state: "While Using the App",
                status: .needsAction,
                kind: .location,
                hint: "Choose Always",
                fix: .openSettings
            )
        case .denied:
            PermissionRow(
                title: "Location",
                state: "Off",
                status: .needsAction,
                kind: .location,
                hint: "Choose Always",
                fix: .openSettings
            )
        case .notDecided:
            PermissionRow(
                title: "Location",
                state: "Not asked yet",
                status: .needsAction,
                kind: .location,
                fix: .action("Continue") {
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
            PermissionRow(title: "Notifications", state: "On", status: .granted, kind: .notifications)
        case .denied:
            PermissionRow(
                title: "Notifications",
                state: "Off",
                status: .needsAction,
                kind: .notifications,
                fix: .openSettings
            )
        case .notDecided:
            PermissionRow(title: "Notifications", state: "Not asked yet", status: .waiting, kind: .notifications)
        }
    }
}

private struct PermissionRow: View {
    enum Kind: String {
        case location
        case notifications
    }

    enum Status {
        case granted
        case needsAction
        case waiting
    }

    enum Fix {
        case openSettings
        case action(LocalizedStringKey, () -> Void)
    }

    let title: LocalizedStringKey
    let state: LocalizedStringKey
    let status: Status
    let kind: Kind
    var hint: LocalizedStringKey?
    var fix: Fix?

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StateRow(state: state, kind: pill) {
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

    private var pill: StatePill.Kind {
        switch status {
        case .granted: .fine
        case .needsAction: .problem
        case .waiting: .neutral(systemImage: "hourglass")
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
