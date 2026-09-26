import Foundation
import RATPCore

extension LocationService {
    static func makeForThisBuild() -> LocationService {
        #if DEBUG
        let sourceStore = LocationSourceStore(storage: UserDefaults.standard)
        if ProcessInfo.processInfo.arguments.contains("--reset-location-source") {
            sourceStore.save(.realGPS)
        }
        return LocationService(realProvider: CoreLocationProvider(), sourceStore: sourceStore)
        #else
        LocationService(realProvider: CoreLocationProvider(), sourceStore: nil)
        #endif
    }
}
