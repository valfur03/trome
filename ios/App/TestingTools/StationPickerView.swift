#if DEBUG
import RATPCore
import SwiftUI

struct StationPickerView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.stationCatalog) private var stationCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        List(filteredStations) { station in
            Button {
                locationService.use(.fake(station.fakePosition))
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
                    if locationService.source == .fake(station.fakePosition) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityIdentifier("station-\(station.name)")
        }
        .searchable(text: $searchText)
        .navigationTitle("Pick a station")
    }

    private var filteredStations: [Station] {
        let stations = stationCatalog.stations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else {
            return stations
        }
        return stations.filter { $0.name.localizedStandardContains(searchText) }
    }
}
#endif
