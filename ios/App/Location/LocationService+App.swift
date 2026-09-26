import Foundation
import RATPCore

extension LocationService {
    static func makeForThisBuild() -> LocationService {
        #if DEBUG
        let sourceStore = LocationSourceStore(storage: UserDefaults.standard)
        sourceStore.resetIfAsked(by: ProcessInfo.processInfo.arguments)
        return LocationService(realProvider: CoreLocationProvider(), sourceStore: sourceStore)
        #else
        LocationService(realProvider: CoreLocationProvider(), sourceStore: nil)
        #endif
    }
}
