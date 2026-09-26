import Foundation
import Observation

public enum NearestStationState: Equatable, Sendable {
    case idle
    case locating
    case permissionUndecided
    case permissionDenied
    case found(NearbyStation)
    case noStationNearby
    case locationUnavailable

    var isFound: Bool {
        if case .found = self { true } else { false }
    }
}

@MainActor
@Observable
public final class NearestStationModel {
    public private(set) var state: NearestStationState = .idle

    private let locationProvider: any LocationProvider
    private let catalog: StationCatalog
    private var isRefreshing = false

    public init(locationProvider: any LocationProvider, catalog: StationCatalog) {
        self.locationProvider = locationProvider
        self.catalog = catalog
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var authorization = locationProvider.authorization
        if authorization == .notDetermined {
            authorization = await locationProvider.requestAuthorization()
        }

        switch authorization {
        case .notDetermined:
            state = .permissionUndecided
        case .denied:
            state = .permissionDenied
        case .authorized:
            await locateNearestStation()
        }
    }

    private func locateNearestStation() async {
        if !state.isFound {
            state = .locating
        }
        do {
            let coordinate = try await locationProvider.currentCoordinate()
            if let nearby = catalog.nearestStation(to: coordinate) {
                state = .found(nearby)
            } else {
                state = .noStationNearby
            }
        } catch {
            state = .locationUnavailable
        }
    }
}
