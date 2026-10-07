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
        NightCard {
            Toggle(isOn: isOn) {
                Label {
                    Text("Automatic mode")
                        .font(.headline)
                } icon: {
                    IconChip {
                        PositionWaitIcon(systemImage: "location.fill", isWaiting: isTurningOn)
                    }
                }
                .labelStyle(.rowTitle)
            }
            .tint(NightLook.fine)
            .accessibilityIdentifier("automaticModeToggle")
            if automaticMode.mode != .turnedOff {
                NightDivider()
            }
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
                    ChipLabel(title: Text("Cancel the snooze")) {
                        PositionWaitIcon(systemImage: "bell", isWaiting: isCancellingTheSnooze)
                    }
                }
                .buttonStyle(.plain)
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
                    ChipLabel(title: Text("Cancel the pause at \(paused.station.name)")) {
                        PositionWaitIcon(systemImage: "arrow.uturn.backward", isWaiting: isCancellingThePause)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cancelStationPause")
            } else if automaticMode.mode != .turnedOff, autoLiveActivity.cannotFindPosition {
                Label("Can’t find your position for now", systemImage: "location.slash")
                    .font(.subheadline)
                    .accessibilityIdentifier("positionNotFound")
            }
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
            ChipLabel("Snooze", systemImage: "bell.slash")
        }
        .accessibilityIdentifier("snoozeMenu")
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
        StateRow(state: "Snoozed", kind: .neutral(systemImage: "bell.slash.fill")) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Back on at \(end, style: .time)")
                    .font(.headline)
                Text(.currentDate, format: .reference(to: end, allowedFields: [.hour, .minute]))
                    .font(.footnote)
                    .foregroundStyle(NightLook.secondaryText)
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
                .font(.headline)
            Text(.currentDate, format: .reference(to: paused.end, allowedFields: [.hour, .minute]))
                .font(.footnote)
                .foregroundStyle(NightLook.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationPauseState")
    }
}
