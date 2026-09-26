import CoreLocation
import RATPCore
import UIKit

@MainActor
final class CoreLocationPermission: NSObject, LocationPermission {
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

extension CoreLocationPermission: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationDidChange()
        }
    }
}
