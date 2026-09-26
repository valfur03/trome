import RATPCore
import SwiftUI

@main
struct RATPActivityApp: App {
    @State private var locationService: LocationService
    @State private var nearestStationModel: NearestStationModel
    @State private var currentStationModel: CurrentStationModel
    @State private var nextTrainsModel: NextTrainsModel
    private let stationCatalog: StationCatalog
    private let primConfiguration = PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)

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
        _currentStationModel = State(
            initialValue: CurrentStationModel(
                catalog: stationCatalog,
                store: CurrentStationStore(storage: UserDefaults.standard)
            )
        )
        _nextTrainsModel = State(
            initialValue: NextTrainsModel(
                provider: primConfiguration.map { PRIMDeparturesProvider(apiKey: $0.apiKey) }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(nearestStationModel: nearestStationModel, primConfiguration: primConfiguration)
                .environment(locationService)
                .environment(currentStationModel)
                .environment(nextTrainsModel)
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
