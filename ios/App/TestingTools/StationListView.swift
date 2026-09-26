#if DEBUG
import RATPCore
import SwiftUI

struct StationListView: View {
    @Environment(\.stationCatalog) private var stationCatalog
    @State private var searchText = ""

    var body: some View {
        let stations = stationCatalog.stations(matching: searchText)
        List {
            Section {
                ForEach(stations) { station in
                    VStack(alignment: .leading) {
                        Text(station.name)
                        Text(station.lines.map(\.displayName).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("stationRow")
                }
            } header: {
                Text(stations.count == 1 ? "1 station" : "\(stations.count) stations")
                    .accessibilityIdentifier("stationCount")
            }
        }
        .overlay {
            if stations.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station name")
        .autocorrectionDisabled()
        .navigationTitle("All stations")
    }
}
#endif
