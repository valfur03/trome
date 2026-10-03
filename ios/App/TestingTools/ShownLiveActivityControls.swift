#if DEBUG
import TROMECore
import SwiftUI

struct ShownLiveActivityControls: View {
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        if let shownStation = autoLiveActivity.shownStation {
            Text(verbatim: "On the lock screen: \(shownStation.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("testingToolsLiveActivityStationName")
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
#endif
