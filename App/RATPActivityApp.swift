import RATPCore
import SwiftUI

@main
struct RATPActivityApp: App {
    @State private var locationService: LocationService
    @State private var nearestStationModel: NearestStationModel

    init() {
        let locationService = LocationService.makeForThisBuild()
        _locationService = State(initialValue: locationService)
        _nearestStationModel = State(
            initialValue: NearestStationModel(
                permission: CoreLocationPermission(),
                locationService: locationService,
                catalog: Self.loadStationCatalog()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(nearestStationModel: nearestStationModel)
                .environment(locationService)
        }
    }

    private static func loadStationCatalog() -> StationCatalog {
        do {
            return try StationCatalog.bundled()
        } catch {
            fatalError("The bundled station list cannot be read: \(error)")
        }
    }
}
