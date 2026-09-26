#if DEBUG
import RATPCore
import SwiftUI

struct LiveActivityControls: View {
    let station: Station?

    @Environment(NextTrainsModel.self) private var nextTrains
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(AutoLiveActivityModel.self) private var autoLiveActivity

    var body: some View {
        VStack(spacing: 8) {
            if liveActivity.isShowing {
                ShownLiveActivityControls()
            } else if let station {
                Button {
                    Task { await autoLiveActivity.startByHand(station) }
                } label: {
                    ButtonLabel("Show on the lock screen", systemImage: "lock.iphone")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .adaptiveButtonBorderShape()
                .accessibilityIdentifier("startLiveActivity")
            }
            LiveActivityStartError()
        }
        .onChange(of: station.map { LiveActivityContentKey(stationId: $0.id, trains: nextTrains.state(for: $0)) }) {
            guard let station else { return }
            Task { await autoLiveActivity.screenTrainsChanged(for: station) }
        }
    }
}

private struct LiveActivityContentKey: Equatable {
    let stationId: String
    let trains: NextTrainsState
}
#endif
