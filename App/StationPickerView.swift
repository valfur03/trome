#if DEBUG
import RATPCore
import SwiftUI

struct StationPickerView: View {
    @Environment(LocationService.self) private var locationService
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
                        Text(station.lines.joined(separator: " · "))
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

    private var filteredStations: [TestPlace] {
        guard !searchText.isEmpty else {
            return TestPlaces.stations
        }
        return TestPlaces.stations.filter { $0.name.localizedStandardContains(searchText) }
    }
}
#endif
