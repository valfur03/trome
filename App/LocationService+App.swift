import Foundation
import RATPCore

extension LocationService {
    static func makeForThisBuild() -> LocationService {
        #if DEBUG
        LocationService(
            realProvider: CoreLocationProvider(),
            sourceStore: LocationSourceStore(storage: UserDefaults.standard)
        )
        #else
        LocationService(realProvider: CoreLocationProvider(), sourceStore: nil)
        #endif
    }
}
