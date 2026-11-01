import CoreLocation
import os
import TROMECore

@MainActor
final class CoreLocationBackgroundLocationKeeper: NSObject, BackgroundLocationKeeper {
    var onPosition: (@MainActor (PositionFix) -> Void)?
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private var isKeeping = false

    override init() {
        super.init()
        manager.delegate = self
        // The switch and the end decide on these positions in the background, within 150 and 250 meters of a station.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        #if DEBUG
        letUITestsEndIt()
        #endif
    }

    func begin() {
        guard !isKeeping else { return }
        #if DEBUG
        guard !Self.isEndedForUITests else { return }
        #endif
        Self.log("begin")
        isKeeping = true
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        updateSession()
    }

    func end() {
        if isKeeping {
            Self.log("end")
        }
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

extension CoreLocationBackgroundLocationKeeper {
    nonisolated private static let logger = Logger(category: "BackgroundLocation")

    nonisolated static func log(_ event: String) {
        #if DEBUG
        logger.notice("background location: \(event, privacy: .public)")
        #endif
    }
}

extension CoreLocationBackgroundLocationKeeper: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last.flatMap(PositionFix.init) else { return }
        MainActor.assumeIsolated {
            guard isKeeping else { return }
            onPosition?(fix)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            updateSession()
        }
    }
}
