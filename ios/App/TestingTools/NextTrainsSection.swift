#if DEBUG
import TROMECore
import SwiftUI

struct NextTrainsSection: View {
    @Environment(CurrentStationModel.self) private var currentStation
    @Environment(NextTrainsModel.self) private var nextTrains
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            if let station = currentStation.station {
                Text(station.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("currentStationName")
                NavigationLink("Change station") {
                    StationSearchView()
                }
                .accessibilityIdentifier("changeStation")
                LiveActivityControls(station: station)
                NextTrainsView(state: nextTrains.state)
                    .task(id: RefreshKey(stationId: station.id, isActive: scenePhase == .active)) {
                        guard scenePhase == .active else { return }
                        await nextTrains.keepUpdated(for: station)
                    }
            } else {
                Text("Pick a metro or RER station to see its next trains.")
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("noStationPickedMessage")
                NavigationLink("Pick a station") {
                    StationSearchView()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chooseStation")
                LiveActivityControls(station: nil)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RefreshKey: Hashable {
    let stationId: String
    let isActive: Bool
}
#endif
