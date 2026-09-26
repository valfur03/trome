#if DEBUG
import RATPCore
import SwiftUI

struct StationSearchView: View {
    @Environment(CurrentStationModel.self) private var currentStation
    @Environment(\.stationCatalog) private var stationCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        let stations = stationCatalog.stations(matching: searchText)
        List(stations) { station in
            Button {
                currentStation.select(station)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(station.name)
                            .foregroundStyle(.primary)
                        Text(station.lines.map(\.displayName).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if currentStation.station?.id == station.id {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("Current station")
                    }
                }
            }
            .accessibilityIdentifier("chooseStation-\(station.name)")
        }
        .overlay {
            if stations.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station name")
        .autocorrectionDisabled()
        .navigationTitle("Pick a station")
    }
}
#endif
