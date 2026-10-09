import AppIntents
import TROMECore
import SwiftUI
import UserNotifications

@main
struct TROMEApp: App {
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
    private let notificationResponseHandler: ArrivalNotificationResponseHandler
    private let primConfiguration = Self.primConfigurationOfThisBuild()
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
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
        let departuresProvider = Self.departuresProvider(primConfiguration: primConfiguration)
        let nextTrainsModel = NextTrainsModel(provider: departuresProvider, catalog: stationCatalog)
        let liveActivityClient = ActivityKitStationLiveActivityClient()
        let liveActivityModel = Self.makeLiveActivityModel(client: liveActivityClient)
        let regionWatcher = Self.makeRegionWatcher(catalog: stationCatalog, locationService: locationService)
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
            regionWatcher: regionWatcher,
            liveActivityRemovals: liveActivityClient
        )
        let notificationResponseHandler = Self.connectSystemEvents(
            to: autoLiveActivityModel, liveActivity: liveActivityModel, regionWatcher: regionWatcher
        )

        #if DEBUG
        uiTestLocationKeeper = CoreLocationBackgroundLocationKeeper.begunIfAsked(by: ProcessInfo.processInfo.arguments)
        autoLiveActivityModel.endLiveActivityIfAsked(by: ProcessInfo.processInfo.arguments)
        #endif
        self.stationCatalog = stationCatalog
        _permissionsModel = State(initialValue: PermissionsModel(locationPermission: permission))
        self.regionWatcher = regionWatcher
        self.notificationResponseHandler = notificationResponseHandler
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
            .environment(\.appName, appName)
            #if DEBUG
            .environment(regionWatcher.wakeLog)
            #endif
        }
    }

    private static func loadStationCatalog() -> StationCatalog {
        do {
            return try StationCatalog.bundled()
        } catch {
            fatalError("The bundled station list cannot be read: \(error)")
        }
    }

    private static func makeLiveActivityModel(
        client: ActivityKitStationLiveActivityClient
    ) -> StationLiveActivityModel {
        StationLiveActivityModel(client: client, store: StationLiveActivityInputsStore(storage: UserDefaults.standard))
    }

    private static func makeAutoLiveActivityModel(
        catalog: StationCatalog,
        liveActivity: StationLiveActivityModel,
        inputs: AutoLiveActivityModel.Inputs,
        regionWatcher: CoreLocationStationRegionWatcher,
        liveActivityRemovals: ActivityKitStationLiveActivityClient
    ) -> AutoLiveActivityModel {
        AutoLiveActivityModel(
            catalog: catalog,
            liveActivity: liveActivity,
            inputs: inputs,
            services: .init(
                notifier: UserNotificationArrivalNotifier(wakeLog: regionWatcher.wakeLog),
                regionWatcher: regionWatcher,
                locationKeeper: CoreLocationBackgroundLocationKeeper(),
                liveActivityRemovals: liveActivityRemovals,
                wakeLog: regionWatcher.wakeLog
            ),
            configuration: .init(
                store: AutoLiveActivityStore(storage: UserDefaults.standard),
                rules: AutoLiveActivityRules(
                    maximumDuration: liveActivityMaximumDuration(),
                    exampleDuration: exampleDuration()
                )
            )
        )
    }

    private static func connectSystemEvents(
        to autoLiveActivityModel: AutoLiveActivityModel,
        liveActivity: StationLiveActivityModel,
        regionWatcher: CoreLocationStationRegionWatcher
    ) -> ArrivalNotificationResponseHandler {
        AppDependencyManager.shared.add(dependency: autoLiveActivityModel)
        AppDependencyManager.shared.add(dependency: liveActivity)
        let notificationResponseHandler = ArrivalNotificationResponseHandler(
            onTap: { [weak autoLiveActivityModel] stationId in
                await autoLiveActivityModel?.notificationTapped(stationId: stationId)
            },
            onAction: { [weak autoLiveActivityModel] action in
                await autoLiveActivityModel?.notificationActionChosen(action)
            }
        )
        UserNotificationArrivalNotifier.registerActions(in: .current())
        UNUserNotificationCenter.current().delegate = notificationResponseHandler
        regionWatcher.onWake = { [weak autoLiveActivityModel] event, lastKnownFix in
            await autoLiveActivityModel?.handleRegionEvent(event, lastKnownFix: lastKnownFix)
        }
        Task { await regionWatcher.resume() }
        return notificationResponseHandler
    }

    private static func makeRegionWatcher(
        catalog: StationCatalog,
        locationService: LocationService
    ) -> CoreLocationStationRegionWatcher {
        let regionWatcher = CoreLocationStationRegionWatcher()
        #if DEBUG
        let wakeLog = WakeLog(storage: UserDefaults.standard)
        wakeLog.recordLaunch(locationSource: locationService.source)
        regionWatcher.wakeLog = wakeLog
        regionWatcher.regionLabel = { WatchedRegion.label(ofId: $0, catalog: catalog) }
        #endif
        return regionWatcher
    }

    private static func primConfigurationOfThisBuild() -> PRIMConfiguration? {
        #if DEBUG
        PRIMConfiguration(infoDictionary: Bundle.main.infoDictionary)
        #else
        nil
        #endif
    }

    private static func departuresProvider(primConfiguration: PRIMConfiguration?) -> (any DeparturesProvider)? {
        #if DEBUG
        let fakeTrains = FakeTrainsStore(storage: UserDefaults.standard).launch(with: ProcessInfo.processInfo.arguments)
        fakeTrains.log(hasTrainDataKey: primConfiguration != nil)
        if let fakeProvider = fakeTrains.provider {
            return fakeProvider
        }
        return primConfiguration.map { PRIMDeparturesProvider.loggingEachAnswer(apiKey: $0.apiKey) }
        #else
        return TrainServerConfiguration(infoDictionary: Bundle.main.infoDictionary).map { server in
            PRIMDeparturesProvider(source: .server(server), httpClient: URLSession(configuration: .ephemeral))
        }
        #endif
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

    private static func exampleDuration() -> TimeInterval {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "exampleDuration")
        if override > 0 {
            return override
        }
        #endif
        return AutoLiveActivityRules.defaultExampleDuration
    }
}
