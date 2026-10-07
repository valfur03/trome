import Foundation

@MainActor
public protocol ArrivalNotifier: AnyObject {
    func requestAuthorization() async
    func notify(_ station: Station) async
    func withdraw()
}

@MainActor
public protocol StationRegionWatcher: AnyObject {
    func watch(_ regions: [WatchedRegion]) async
}

@MainActor
public protocol BackgroundLocationKeeper: AnyObject {
    func begin()
    func end()
}

public struct AutoLiveActivityStore {
    public static let key = "autoLiveActivity.state"

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    public func load() -> AutoLiveActivityState {
        guard let data = storage.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(AutoLiveActivityState.self, from: data) else {
            return AutoLiveActivityState()
        }
        return state
    }

    public func save(_ state: AutoLiveActivityState) {
        storage.set(try? JSONEncoder().encode(state), forKey: Self.key)
    }
}

extension AutoLiveActivityModel {
    public struct Inputs {
        public let locationService: LocationService
        public let permission: any LocationPermission
        public let screenTrains: NextTrainsModel
        public let liveActivityTrains: NextTrainsModel
        public let automaticMode: AutomaticModeModel

        public init(
            locationService: LocationService,
            permission: any LocationPermission,
            screenTrains: NextTrainsModel,
            liveActivityTrains: NextTrainsModel,
            automaticMode: AutomaticModeModel
        ) {
            self.locationService = locationService
            self.permission = permission
            self.screenTrains = screenTrains
            self.liveActivityTrains = liveActivityTrains
            self.automaticMode = automaticMode
        }
    }

    public struct Services {
        public let notifier: any ArrivalNotifier
        public let regionWatcher: any StationRegionWatcher
        public let locationKeeper: any BackgroundLocationKeeper
        public let liveActivityRemovals: any LiveActivityRemovalWatcher
        public let wakeLog: WakeLog?

        public init(
            notifier: any ArrivalNotifier,
            regionWatcher: any StationRegionWatcher,
            locationKeeper: any BackgroundLocationKeeper,
            liveActivityRemovals: any LiveActivityRemovalWatcher,
            wakeLog: WakeLog? = nil
        ) {
            self.notifier = notifier
            self.regionWatcher = regionWatcher
            self.locationKeeper = locationKeeper
            self.liveActivityRemovals = liveActivityRemovals
            self.wakeLog = wakeLog
        }
    }

    public struct Configuration {
        public let store: AutoLiveActivityStore
        public let rules: AutoLiveActivityRules
        public let now: @Sendable () -> Date
        public let sleep: @Sendable (Duration) async throws -> Void

        public init(
            store: AutoLiveActivityStore,
            rules: AutoLiveActivityRules = AutoLiveActivityRules(),
            now: @escaping @Sendable () -> Date = { Date() },
            sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        ) {
            self.store = store
            self.rules = rules
            self.now = now
            self.sleep = sleep
        }
    }
}
