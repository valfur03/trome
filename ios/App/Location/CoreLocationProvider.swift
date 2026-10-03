import CoreLocation
import TROMECore

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

    @MainActor
    func currentFix() async -> PositionFix? {
        await CurrentLocationRequest().fix()
    }

    private static func event(from update: CLLocationUpdate) -> LocationEvent? {
        if let fix = update.location.flatMap(PositionFix.init) {
            return .position(fix)
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

@MainActor
private final class CurrentLocationRequest: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PositionFix?, Never>?

    func fix() async -> PositionFix? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.requestLocation()
        }
    }

    private func finish(with fix: PositionFix?) {
        continuation?.resume(returning: fix)
        continuation = nil
        manager.delegate = nil
    }
}

extension CurrentLocationRequest: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.flatMap(PositionFix.init)
        MainActor.assumeIsolated {
            finish(with: fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            finish(with: nil)
        }
    }
}
