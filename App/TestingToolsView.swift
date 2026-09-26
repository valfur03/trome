#if DEBUG
import RATPCore
import SwiftUI

struct TestingToolsView: View {
    let nearestStationModel: NearestStationModel
    let primConfiguration: PRIMConfiguration?

    @Environment(LocationService.self) private var locationService
    @State private var coordinatesText = ""
    @State private var coordinatesError: String?
    @State private var addressText = ""
    @State private var addressError: String?
    @State private var isSearchingAddress = false

    var body: some View {
        Form {
            currentPositionSection
            Section("Fake position") {
                NavigationLink("Pick a station") {
                    StationPickerView()
                }
                .accessibilityIdentifier("pickStation")
                Button("Far from any station") {
                    locationService.use(.fake(TestPlaces.farFromAnyStation))
                }
                .accessibilityIdentifier("farFromAnyStation")
            }
            coordinatesSection
            addressSection
            Section {
                NavigationLink("All stations") {
                    StationListView()
                }
                .accessibilityIdentifier("allStations")
            } header: {
                Text("Station list")
            } footer: {
                Text("Every metro and RER station the app knows, with its lines.")
            }
            Section {
                NavigationLink("Next trains of a station") {
                    NextTrainsScreen(primConfiguration: primConfiguration)
                }
                .accessibilityIdentifier("nextTrains")
            } header: {
                Text("Next trains")
            } footer: {
                Text("Pick a station by hand, see its next trains, and show them on the lock screen.")
            }
        }
        .navigationTitle("Testing tools")
        .task {
            locationService.start()
        }
    }

    private var currentPositionSection: some View {
        Section {
            Text(sourceDescription)
                .accessibilityIdentifier("locationSource")
            Text(positionDescription)
                .monospacedDigit()
                .accessibilityIdentifier("currentPosition")
            nearestStationRow
            Button("Use the real GPS") {
                locationService.use(.realGPS)
            }
            .disabled(locationService.source == .realGPS)
            .accessibilityIdentifier("useRealGPS")
        } header: {
            Text("Position used by the app")
        } footer: {
            Text("Every feature that needs your location uses this position.")
        }
    }

    private var coordinatesSection: some View {
        Section {
            TextField("48.8584, 2.2945", text: $coordinatesText)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .accessibilityIdentifier("coordinatesField")
            Button("Use these coordinates", action: useCoordinates)
                .disabled(coordinatesText.isEmpty)
                .accessibilityIdentifier("useCoordinates")
            if let coordinatesError {
                Text(coordinatesError)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Coordinates")
        } footer: {
            Text("Latitude, then longitude, with a dot for decimals.")
        }
    }

    private var addressSection: some View {
        Section("Address") {
            TextField("Address in or near Paris", text: $addressText)
                .autocorrectionDisabled()
                .accessibilityIdentifier("addressField")
            Button(isSearchingAddress ? "Searching…" : "Find this address") {
                Task { await useAddress() }
            }
            .disabled(isSearchingAddress || addressText.isEmpty)
            .accessibilityIdentifier("findAddress")
            if let addressError {
                Text(addressError)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var nearestStationRow: some View {
        if case .found(let nearby) = nearestStationModel.state {
            VStack(alignment: .leading) {
                Text(nearby.station.name)
                    .accessibilityIdentifier("nearestStationName")
                Text(nearestStationDetails(nearby))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nearestStationLines")
            }
        } else {
            Text(nearestStationProblem)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("nearestStationState")
        }
    }

    private func nearestStationDetails(_ nearby: NearbyStation) -> String {
        let distance = Measurement(value: nearby.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        let lines = nearby.station.lines.map(\.displayName).joined(separator: " · ")
        return "Nearest station, \(distance): \(lines)"
    }

    private var nearestStationProblem: String {
        switch nearestStationModel.state {
        case .idle, .locating, .found:
            "Nearest station: looking…"
        case .permissionUndecided, .permissionDenied:
            "Nearest station: no location access"
        case .noStationNearby:
            "Nearest station: none within walking distance"
        case .locationUnavailable:
            "Nearest station: position unavailable"
        }
    }

    private var positionDescription: String {
        if let position = locationService.position {
            return position.formatted
        }
        switch locationService.problem {
        case .permissionDenied:
            return "Location access is denied"
        case .unavailable:
            return "Location is unavailable"
        case nil:
            return "Waiting for a position…"
        }
    }

    private var sourceDescription: String {
        switch locationService.source {
        case .realGPS:
            "Real GPS"
        case .fake(let fakePosition):
            "Fake: \(fakePosition.name)"
        }
    }

    private func useCoordinates() {
        guard let coordinate = Coordinate(parsing: coordinatesText) else {
            coordinatesError = "These are not valid coordinates."
            return
        }
        coordinatesError = nil
        locationService.use(.fake(FakePosition(name: coordinate.formatted, coordinate: coordinate)))
    }

    private func useAddress() async {
        isSearchingAddress = true
        defer { isSearchingAddress = false }
        do {
            let fakePosition = try await AddressGeocoder().fakePosition(for: addressText)
            addressError = nil
            locationService.use(.fake(fakePosition))
        } catch is AddressGeocoder.NotFound {
            addressError = "No place found for this address."
        } catch {
            addressError = "The address search failed. Check the network and try again."
        }
    }
}
#endif
