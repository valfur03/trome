import CoreLocation
import RATPCore

@MainActor
final class CoreLocationBackgroundLocationKeeper: BackgroundLocationKeeper {
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?

    init() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func begin() {
        guard session == nil else { return }
        session = CLBackgroundActivitySession()
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func end() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        session?.invalidate()
        session = nil
    }
}
