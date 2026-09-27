import RATPCore
import SwiftUI

struct ShownLiveActivityControls: View {
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        if let shownStation = autoLiveActivity.shownStation {
            Text("On the lock screen: \(shownStation.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("liveActivityStationName")
        }
        Button {
            Task { await autoLiveActivity.stopByHand() }
        } label: {
            ButtonLabel("Stop showing on the lock screen", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .adaptiveButtonBorderShape()
        .accessibilityIdentifier("stopLiveActivity")
    }
}

struct LiveActivityStartError: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity

    var body: some View {
        if let error = liveActivity.startError {
            Text(message(for: error))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
                .accessibilityIdentifier("liveActivityError")
        }
    }

    private func message(for error: StationLiveActivityError) -> LocalizedStringKey {
        switch error {
        case .turnedOff:
            "Live Activities are turned off for this app. Turn them on in Settings > RATP Activity."
        case .failed:
            "The lock screen display could not start. Try again."
        }
    }
}
