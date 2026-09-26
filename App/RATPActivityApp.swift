import RATPCore
import SwiftUI
import UserNotifications

@main
struct RATPActivityApp: App {
    @State private var locationService: LocationService
    @State private var nearestStationModel: NearestStationModel
    @State private var currentStationModel: CurrentStationModel
    @State private var nextTrainsModel: NextTrainsModel
    @State private var liveActivityModel: StationLiveActivityModel
    @State private var autoLiveActivityModel: AutoLiveActivityModel
    private let stationCatalog: StationCatalog
    private let locationPermission: CoreLocationPermission
    private let regionWatcher: CoreLocationStationRegionWatcher
    private let notificationTapHandler: ArrivalNotificationTapHandler
    private let primConfiguration = PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)

    init() {
        let locationService = LocationService.makeForThisBuild()
        let stationCatalog = Self.loadStationCatalog()
        let permission = CoreLocationPermission()
        let currentStationModel = CurrentStationModel(
            catalog: stationCatalog,
            store: CurrentStationStore(storage: UserDefaults.standard)
        )
        let nextTrainsModel = NextTrainsModel(provider: Self.departuresProvider(primConfiguration))
        let liveActivityModel = StationLiveActivityModel(client: ActivityKitStationLiveActivityClient())
        let regionWatcher = CoreLocationStationRegionWatcher(catalog: stationCatalog)
        let autoLiveActivityModel = Self.makeAutoLiveActivityModel(
            catalog: stationCatalog,
            liveActivity: liveActivityModel,
            inputs: .init(
                locationService: locationService,
                permission: permission,
                currentStation: currentStationModel,
                screenTrains: nextTrainsModel,
                liveActivityTrains: NextTrainsModel(provider: Self.departuresProvider(primConfiguration))
            ),
            regionWatcher: regionWatcher
        )
        let notificationTapHandler = ArrivalNotificationTapHandler { [weak autoLiveActivityModel] stationId in
            await autoLiveActivityModel?.notificationTapped(stationId: stationId)
        }
        UNUserNotificationCenter.current().delegate = notificationTapHandler
        regionWatcher.onWake = { [weak autoLiveActivityModel] position in
            await autoLiveActivityModel?.handleMonitoredPosition(position)
        }
        Task { await regionWatcher.resume() }

        self.stationCatalog = stationCatalog
        self.locationPermission = permission
        self.regionWatcher = regionWatcher
        self.notificationTapHandler = notificationTapHandler
        _locationService = State(initialValue: locationService)
        _nearestStationModel = State(
            initialValue: NearestStationModel(
                permission: permission,
                locationService: locationService,
                catalog: stationCatalog
            )
        )
        _currentStationModel = State(initialValue: currentStationModel)
        _nextTrainsModel = State(initialValue: nextTrainsModel)
        _liveActivityModel = State(initialValue: liveActivityModel)
        _autoLiveActivityModel = State(initialValue: autoLiveActivityModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                nearestStationModel: nearestStationModel,
                locationPermission: locationPermission,
                primConfiguration: primConfiguration
            )
            .environment(locationService)
            .environment(currentStationModel)
            .environment(nextTrainsModel)
            .environment(liveActivityModel)
            .environment(autoLiveActivityModel)
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

    private static func makeAutoLiveActivityModel(
        catalog: StationCatalog,
        liveActivity: StationLiveActivityModel,
        inputs: AutoLiveActivityModel.Inputs,
        regionWatcher: CoreLocationStationRegionWatcher
    ) -> AutoLiveActivityModel {
        AutoLiveActivityModel(
            catalog: catalog,
            liveActivity: liveActivity,
            inputs: inputs,
            services: .init(
                notifier: UserNotificationArrivalNotifier(),
                regionWatcher: regionWatcher,
                locationKeeper: BackgroundActivityLocationKeeper()
            ),
            configuration: .init(
                store: AutoLiveActivityStore(storage: UserDefaults.standard),
                rules: AutoLiveActivityRules(maximumDuration: liveActivityMaximumDuration())
            )
        )
    }

    private static func departuresProvider(_ configuration: PRIMConfiguration?) -> PRIMDeparturesProvider? {
        configuration.map { PRIMDeparturesProvider(apiKey: $0.apiKey) }
    }

    private static func liveActivityMaximumDuration() -> TimeInterval {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "liveActivityMaximumDuration")
        if override > 0 {
            return override
        }
        #endif
        return AutoLiveActivityRules.defaultMaximumDuration
    }
}
