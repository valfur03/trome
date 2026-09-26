import RATPCore
import SwiftUI

@main
struct RATPActivityApp: App {
    @State private var locationService: LocationService
    @State private var nearestStationModel: NearestStationModel
    private let stationCatalog: StationCatalog

    init() {
        let locationService = LocationService.makeForThisBuild()
        let stationCatalog = Self.loadStationCatalog()
        self.stationCatalog = stationCatalog
        _locationService = State(initialValue: locationService)
        _nearestStationModel = State(
            initialValue: NearestStationModel(
                permission: CoreLocationPermission(),
                locationService: locationService,
                catalog: stationCatalog
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(nearestStationModel: nearestStationModel)
                .environment(locationService)
                .environment(\.stationCatalog, stationCatalog)
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
