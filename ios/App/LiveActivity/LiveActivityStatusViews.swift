import RATPCore
import SwiftUI

struct ShownLiveActivityControls: View {
    /// False on the testing tools, which stay in English (CLAUDE.md, "Texts in French and English").
    var translatesTexts = true

    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        if let shownStation = autoLiveActivity.shownStation {
            stationText(shownStation.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("liveActivityStationName")
        }
        Button {
            Task { await autoLiveActivity.stopByHand() }
        } label: {
            ButtonLabel(stopTitle, systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .adaptiveButtonBorderShape()
        .accessibilityIdentifier("stopLiveActivity")
    }

    private func stationText(_ name: String) -> Text {
        translatesTexts ? Text("On the lock screen: \(name)") : Text(verbatim: "On the lock screen: \(name)")
    }

    private var stopTitle: Text {
        translatesTexts ? Text("Stop showing on the lock screen") : Text(verbatim: "Stop showing on the lock screen")
    }
}

struct LiveActivityStartError: View {
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(\.appName) private var appName

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
            "Live Activities are turned off for this app. Turn them on in Settings > \(appName)."
        case .failed:
            "The lock screen display could not start. Try again."
        }
    }
}
