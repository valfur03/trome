import AppIntents
import RATPCore
import SwiftUI
import UserNotifications

@main
struct RATPActivityApp: App {
    @State private var locationService: LocationService
    @State private var nearestStationModel: NearestStationModel
    @State private var permissionsModel: PermissionsModel
    @State private var currentStationModel: CurrentStationModel
    @State private var nextTrainsModel: NextTrainsModel
    @State private var liveActivityModel: StationLiveActivityModel
    @State private var autoLiveActivityModel: AutoLiveActivityModel
    @State private var automaticModeModel: AutomaticModeModel
    private let stationCatalog: StationCatalog
    private let regionWatcher: CoreLocationStationRegionWatcher
    private let notificationTapHandler: ArrivalNotificationTapHandler
    private let primConfiguration = PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)
    #if DEBUG
    private let uiTestLocationKeeper: CoreLocationBackgroundLocationKeeper?
    #endif

    init() {
        let locationService = LocationService.makeForThisBuild()
        let stationCatalog = Self.loadStationCatalog()
        let permission = CoreLocationPermission()
        let currentStationModel = CurrentStationModel(
            catalog: stationCatalog,
            store: CurrentStationStore(storage: UserDefaults.standard)
        )
        let departuresProvider = Self.departuresProvider(primConfiguration)
        let nextTrainsModel = NextTrainsModel(provider: departuresProvider, catalog: stationCatalog)
        let liveActivityModel = StationLiveActivityModel(client: ActivityKitStationLiveActivityClient())
        let regionWatcher = CoreLocationStationRegionWatcher()
        let automaticModeModel = AutomaticModeModel(store: AutomaticModeStore(storage: UserDefaults.standard))
        let autoLiveActivityModel = Self.makeAutoLiveActivityModel(
            catalog: stationCatalog,
            liveActivity: liveActivityModel,
            inputs: .init(
                locationService: locationService,
                permission: permission,
                screenTrains: nextTrainsModel,
                liveActivityTrains: NextTrainsModel(provider: departuresProvider, catalog: stationCatalog),
                automaticMode: automaticModeModel
            ),
            regionWatcher: regionWatcher
        )
        let notificationTapHandler = Self.connectSystemEvents(
            to: autoLiveActivityModel, liveActivity: liveActivityModel, regionWatcher: regionWatcher
        )

        #if DEBUG
        uiTestLocationKeeper = CoreLocationBackgroundLocationKeeper.begunIfAsked(by: ProcessInfo.processInfo.arguments)
        #endif
        self.stationCatalog = stationCatalog
        _permissionsModel = State(initialValue: PermissionsModel(locationPermission: permission))
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
        _automaticModeModel = State(initialValue: automaticModeModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                nearestStationModel: nearestStationModel,
                permissions: permissionsModel,
                primConfiguration: primConfiguration
            )
            .environment(locationService)
            .environment(currentStationModel)
            .environment(nextTrainsModel)
            .environment(liveActivityModel)
            .environment(autoLiveActivityModel)
            .environment(automaticModeModel)
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
                locationKeeper: CoreLocationBackgroundLocationKeeper()
            ),
            configuration: .init(
                store: AutoLiveActivityStore(storage: UserDefaults.standard),
                rules: AutoLiveActivityRules(maximumDuration: liveActivityMaximumDuration())
            )
        )
    }

    private static func connectSystemEvents(
        to autoLiveActivityModel: AutoLiveActivityModel,
        liveActivity: StationLiveActivityModel,
        regionWatcher: CoreLocationStationRegionWatcher
    ) -> ArrivalNotificationTapHandler {
        AppDependencyManager.shared.add(dependency: autoLiveActivityModel)
        AppDependencyManager.shared.add(dependency: liveActivity)
        let notificationTapHandler = ArrivalNotificationTapHandler { [weak autoLiveActivityModel] stationId in
            await autoLiveActivityModel?.notificationTapped(stationId: stationId)
        }
        UNUserNotificationCenter.current().delegate = notificationTapHandler
        regionWatcher.onWake = { [weak autoLiveActivityModel] enteredRegionId, lastKnownFix in
            await autoLiveActivityModel?.handleRegionEvent(enteredRegionId: enteredRegionId, lastKnownFix: lastKnownFix)
        }
        Task { await regionWatcher.resume() }
        return notificationTapHandler
    }

    private static func departuresProvider(_ configuration: PRIMConfiguration?) -> (any DeparturesProvider)? {
        #if DEBUG
        if let fakeProvider = FakeDeparturesProvider.ifAsked(by: ProcessInfo.processInfo.arguments) {
            return fakeProvider
        }
        #endif
        return configuration.map { PRIMDeparturesProvider(apiKey: $0.apiKey) }
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
