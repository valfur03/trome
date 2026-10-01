import RATPCore
import SwiftUI

struct AutomaticModeSection: View {
    @Environment(AutomaticModeModel.self) private var automaticMode
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    private var isOn: Binding<Bool> {
        Binding {
            automaticMode.mode != .turnedOff
        } set: { isOn in
            automaticMode.setOn(isOn)
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: isOn) {
                Label("Automatic mode", systemImage: "location.circle")
            }
            .accessibilityIdentifier("automaticModeToggle")
            switch automaticMode.mode {
            case .turnedOn:
                snoozeMenu
            case .snoozed(let end):
                SnoozeState(end: end)
                Button("Cancel the snooze", systemImage: "bell") {
                    automaticMode.cancelSnooze()
                }
                .accessibilityIdentifier("cancelSnooze")
            case .turnedOff:
                EmptyView()
            }
            if automaticMode.mode != .turnedOff, let paused = autoLiveActivity.pausedStation {
                PauseState(paused: paused)
                Button("Cancel the pause at \(paused.station.name)", systemImage: "arrow.uturn.backward") {
                    Task { await autoLiveActivity.cancelPause() }
                }
                .accessibilityIdentifier("cancelStationPause")
            }
        } footer: {
            Text(footer)
        }
    }

    private var snoozeMenu: some View {
        Menu {
            ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                Button(title(of: duration)) {
                    Task { await autoLiveActivity.snooze(for: duration) }
                }
                .accessibilityIdentifier("snooze-\(duration.rawValue)")
            }
        } label: {
            Label("Snooze", systemImage: "bell.slash")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .accessibilityIdentifier("snoozeMenu")
    }

    private var footer: LocalizedStringKey {
        switch automaticMode.mode {
        case .turnedOn:
            """
            The Live Activity starts by itself when you come near a metro or RER station, \
            and stops when you leave. Snooze it to stop it for a while.
            """
        case .snoozed:
            """
            No notification and no automatic Live Activity until the snooze ends. \
            You can still show the Live Activity by hand.
            """
        case .turnedOff:
            "No notification and no automatic Live Activity. You can still show the Live Activity by hand."
        }
    }

    private func title(of duration: SnoozeDuration) -> LocalizedStringKey {
        switch duration {
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .restOfToday: "For the rest of today"
        }
    }
}

private struct SnoozeState: View {
    let end: Date

    var body: some View {
        StateRow(state: "Snoozed") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Back on at \(end, style: .time)")
                Text(.currentDate, format: .reference(to: end, allowedFields: [.hour, .minute]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("snoozeState")
    }
}

private struct PauseState: View {
    let paused: PausedStation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Paused at \(paused.station.name) until \(paused.end, style: .time)")
            Text(.currentDate, format: .reference(to: paused.end, allowedFields: [.hour, .minute]))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationPauseState")
    }
}
