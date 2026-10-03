import TROMECore
import SwiftUI

struct AutomaticModeSection: View {
    @Environment(AutomaticModeModel.self) private var automaticMode
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity
    @State private var isTurningOn = false
    @State private var isCancellingTheSnooze = false
    @State private var isCancellingThePause = false

    private var isOn: Binding<Bool> {
        Binding {
            automaticMode.mode != .turnedOff
        } set: { isOn in
            automaticMode.setOn(isOn)
            guard isOn, !isTurningOn else { return }
            isTurningOn = true
            Task {
                await autoLiveActivity.automaticModeTurnedOn()
                isTurningOn = false
            }
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: isOn) {
                Label {
                    Text("Automatic mode")
                } icon: {
                    PositionWaitIcon(systemImage: "location.circle", isWaiting: isTurningOn)
                }
            }
            .accessibilityIdentifier("automaticModeToggle")
            switch automaticMode.mode {
            case .turnedOn:
                snoozeMenu
            case .snoozed(let end):
                SnoozeState(end: end)
                Button {
                    guard !isCancellingTheSnooze else { return }
                    isCancellingTheSnooze = true
                    Task {
                        await autoLiveActivity.cancelSnooze()
                        isCancellingTheSnooze = false
                    }
                } label: {
                    Label {
                        Text("Cancel the snooze")
                    } icon: {
                        PositionWaitIcon(systemImage: "bell", isWaiting: isCancellingTheSnooze)
                    }
                }
                .accessibilityIdentifier("cancelSnooze")
            case .turnedOff:
                EmptyView()
            }
            if automaticMode.mode != .turnedOff, let paused = autoLiveActivity.pausedStation {
                PauseState(paused: paused)
                Button {
                    guard !isCancellingThePause else { return }
                    isCancellingThePause = true
                    Task {
                        await autoLiveActivity.cancelPause()
                        isCancellingThePause = false
                    }
                } label: {
                    Label {
                        Text("Cancel the pause at \(paused.station.name)")
                    } icon: {
                        PositionWaitIcon(systemImage: "arrow.uturn.backward", isWaiting: isCancellingThePause)
                    }
                }
                .accessibilityIdentifier("cancelStationPause")
            } else if automaticMode.mode != .turnedOff, autoLiveActivity.cannotFindPosition {
                Label("Can’t find your position for now", systemImage: "location.slash")
                    .accessibilityIdentifier("positionNotFound")
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
            "No notification and no automatic Live Activity until the snooze ends."
        case .turnedOff:
            "No notification and no automatic Live Activity."
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
