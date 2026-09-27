import CoreLocation
import RATPCore

@MainActor
final class CoreLocationBackgroundLocationKeeper: NSObject, BackgroundLocationKeeper {
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private var isKeeping = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
    }

    func begin() {
        guard !isKeeping else { return }
        isKeeping = true
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        updateSession()
    }

    func end() {
        isKeeping = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        updateSession()
    }

    private func updateSession() {
        guard isKeeping, manager.authorizationStatus != .authorizedAlways else {
            session?.invalidate()
            session = nil
            return
        }
        if session == nil {
            session = CLBackgroundActivitySession()
        }
    }
}

extension CoreLocationBackgroundLocationKeeper: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            updateSession()
        }
    }
}
