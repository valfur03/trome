import CoreLocation
import RATPCore

struct CoreLocationProvider: LocationProvider {
    func events() -> AsyncStream<LocationEvent> {
        AsyncStream { continuation in
            let task = Task {
                let session = CLServiceSession(authorization: .whenInUse)
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let event = Self.event(from: update) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.problem(.unavailable))
                    }
                }
                withExtendedLifetime(session) {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func event(from update: CLLocationUpdate) -> LocationEvent? {
        if let location = update.location,
           let coordinate = Coordinate(
               latitude: location.coordinate.latitude,
               longitude: location.coordinate.longitude
           ) {
            return .position(coordinate)
        }
        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
            return .problem(.permissionDenied)
        }
        if update.locationUnavailable {
            return .problem(.unavailable)
        }
        return nil
    }
}
