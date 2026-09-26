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
                if let shownStation = autoLiveActivity.shownStation {
                    Text("On the lock screen: \(shownStation.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("liveActivityStationName")
                }
                Button("Stop showing on the lock screen", systemImage: "xmark.circle") {
                    Task { await autoLiveActivity.stopByHand() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopLiveActivity")
            } else if let station {
                Button("Show on the lock screen", systemImage: "lock.iphone") {
                    Task { await autoLiveActivity.startByHand(station) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("startLiveActivity")
            }
            if let error = liveActivity.startError {
                Text(message(for: error))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("liveActivityError")
            }
        }
        .onChange(of: station.map { LiveActivityContentKey(stationId: $0.id, trains: nextTrains.state(for: $0)) }) {
            guard let station else { return }
            Task { await autoLiveActivity.screenTrainsChanged(for: station) }
        }
    }

    private func message(for error: StationLiveActivityError) -> String {
        switch error {
        case .turnedOff:
            "Live Activities are turned off for this app. Turn them on in Settings > RATP Activity."
        case .failed:
            "The lock screen display could not start. Try again."
        }
    }
}

private struct LiveActivityContentKey: Equatable {
    let stationId: String
    let trains: NextTrainsState
}
