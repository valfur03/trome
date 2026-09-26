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
}

@MainActor
@Observable
public final class NearestStationModel {
    public private(set) var state: NearestStationState = .idle

    private let permission: any LocationPermission
    private let locationService: LocationService
    private let catalog: StationCatalog
    private let positionTimeout: Duration
    private var isRefreshing = false
    private var isFollowingPosition = false
    private var positionTimeoutTask: Task<Void, Never>?

    public init(
        permission: any LocationPermission,
        locationService: LocationService,
        catalog: StationCatalog,
        positionTimeout: Duration = .seconds(20)
    ) {
        self.permission = permission
        self.locationService = locationService
        self.catalog = catalog
        self.positionTimeout = positionTimeout
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var authorization = permission.authorization
        if authorization == .notDetermined {
            authorization = await permission.requestAuthorization()
        }

        switch authorization {
        case .notDetermined:
            state = .permissionUndecided
        case .denied:
            state = .permissionDenied
        case .authorized:
            locationService.start()
            followPosition()
            showNearestStation()
        }
    }

    private func followPosition() {
        guard !isFollowingPosition else { return }
        isFollowingPosition = true
        observePosition()
    }

    private func observePosition() {
        withObservationTracking {
            _ = locationService.position
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.positionDidChange()
            }
        }
    }

    private func positionDidChange() {
        observePosition()
        guard permission.authorization == .authorized else { return }
        showNearestStation()
    }

    private func showNearestStation() {
        guard let position = locationService.position else {
            waitForPosition()
            return
        }
        positionTimeoutTask?.cancel()
        positionTimeoutTask = nil
        if let nearby = catalog.nearestStation(to: position) {
            state = .found(nearby)
        } else {
            state = .noStationNearby
        }
    }

    private func waitForPosition() {
        state = .locating
        guard positionTimeoutTask == nil else { return }
        positionTimeoutTask = Task { [weak self, positionTimeout] in
            try? await Task.sleep(for: positionTimeout)
            guard !Task.isCancelled else { return }
            self?.positionDidTimeOut()
        }
    }

    private func positionDidTimeOut() {
        positionTimeoutTask = nil
        guard state == .locating, locationService.position == nil else { return }
        state = .locationUnavailable
    }
}
