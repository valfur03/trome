#if os(iOS)
import CoreLocation

public struct CoreLocationProvider: LocationProvider {
    public init() {}

    public func positions() -> AsyncStream<Coordinate> {
        AsyncStream { continuation in
            let task = Task {
                let session = CLServiceSession(authorization: .whenInUse)
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location,
                           let coordinate = Coordinate(
                               latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude
                           ) {
                            continuation.yield(coordinate)
                        }
                    }
                } catch {}
                withExtendedLifetime(session) {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
