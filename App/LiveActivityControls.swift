import RATPCore
import SwiftUI

struct LiveActivityControls: View {
    let station: Station

    @Environment(NextTrainsModel.self) private var nextTrains
    @Environment(StationLiveActivityModel.self) private var liveActivity
    @Environment(\.scenePhase) private var scenePhase

    private var trains: NextTrainsState {
        nextTrains.state(for: station)
    }

    var body: some View {
        VStack(spacing: 8) {
            if liveActivity.isShowing {
                Button("Stop showing on the lock screen", systemImage: "xmark.circle") {
                    Task { await liveActivity.stop() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stopLiveActivity")
            } else {
                Button("Show on the lock screen", systemImage: "lock.iphone") {
                    Task { await liveActivity.start(station: station, trains: trains) }
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
        .onChange(of: LiveActivityContentKey(stationId: station.id, trains: trains)) {
            Task { await liveActivity.update(station: station, trains: trains) }
        }
        .onChange(of: scenePhase, initial: true) {
            guard scenePhase == .active else { return }
            liveActivity.syncWithSystem()
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
