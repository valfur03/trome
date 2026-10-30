import Foundation
import TROMECore

extension LocationService {
    static func makeForThisBuild() -> LocationService {
        #if DEBUG
        let sourceStore = LocationSourceStore(storage: UserDefaults.standard)
        sourceStore.resetIfAsked(by: ProcessInfo.processInfo.arguments)
        let service = LocationService(realProvider: CoreLocationProvider(), sourceStore: sourceStore)
        UITestLocationEnd.listen(stopping: service)
        return service
        #else
        LocationService(realProvider: CoreLocationProvider(), sourceStore: nil)
        #endif
    }
}
