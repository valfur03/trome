import CoreLocation
import RATPCore
import UIKit

@MainActor
final class CoreLocationProvider: NSObject, LocationProvider {
    enum Failure: Error {
        case timedOut
        case noPosition
    }

    private static let positionTimeout: Duration = .seconds(20)

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var backgroundObserver: NSObjectProtocol?

    override init() {
        super.init()
        manager.delegate = self
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resumeAuthorizationWaiters()
            }
        }
    }

    var authorization: LocationAuthorization {
        Self.authorization(from: manager.authorizationStatus)
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            if authorizationWaiters.count == 1 {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    func currentCoordinate() async throws -> Coordinate {
        try await withThrowingTaskGroup(of: Coordinate.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return Coordinate(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    }
                }
                throw Failure.noPosition
            }
            group.addTask {
                try await Task.sleep(for: Self.positionTimeout)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let coordinate = try await group.next() else { throw Failure.noPosition }
            return coordinate
        }
    }

    private func authorizationDidChange() {
        guard authorization != .notDetermined else { return }
        resumeAuthorizationWaiters()
    }

    private func resumeAuthorizationWaiters() {
        let current = authorization
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume(returning: current) }
    }

    private static func authorization(from status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationDidChange()
        }
    }
}
