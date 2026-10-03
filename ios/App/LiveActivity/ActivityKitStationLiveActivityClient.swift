import ActivityKit
import TROMECore
import Synchronization

@MainActor
final class ActivityKitStationLiveActivityClient: StationLiveActivityClient {
    private nonisolated static var runningActivities: [Activity<StationActivityAttributes>] {
        Activity<StationActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private nonisolated let idsEndedByTheApp = Mutex<Set<String>>([])
    private var followedIds: Set<String> = []
    private var onRemoval: (@MainActor (LiveActivityRemoval) -> Void)?

    init() {
        #if DEBUG
        Self.logLaunch(Activity<StationActivityAttributes>.activities)
        #endif
        Activity<StationActivityAttributes>.activities.forEach(follow)
        Task { [weak self] in
            for await activity in Activity<StationActivityAttributes>.activityUpdates {
                self?.follow(activity)
            }
        }
    }

    var isShowing: Bool {
        !Self.runningActivities.isEmpty
    }

    var shownContent: StationActivityAttributes.ContentState? {
        Self.runningActivities.first?.content.state
    }

    func start(_ content: StationActivityAttributes.ContentState) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw StationLiveActivityError.turnedOff
        }
        _ = try Activity.request(
            attributes: StationActivityAttributes(),
            content: ActivityContent(state: content, staleDate: content.staleDate),
            pushType: nil
        )
        #if DEBUG
        Self.log(content, sentBy: "start")
        #endif
    }

    nonisolated func update(_ content: StationActivityAttributes.ContentState) async {
        let activities = Self.runningActivities
        #if DEBUG
        if !activities.isEmpty {
            Self.log(content, sentBy: "update")
        }
        #endif
        for activity in activities {
            await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
        }
    }

    nonisolated func end() async {
        let activities = Activity<StationActivityAttributes>.activities
        #if DEBUG
        Self.logEnd(of: activities)
        #endif
        idsEndedByTheApp.withLock { $0.formUnion(activities.map(\.id)) }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func follow(_ activity: Activity<StationActivityAttributes>) {
        guard followedIds.insert(activity.id).inserted else { return }
        #if DEBUG
        Self.logFollowed(activity)
        #endif
        Task { [weak self] in
            var isReported = false
            for await state in activity.activityStateUpdates {
                #if DEBUG
                Self.log(state, of: activity.id)
                #endif
                guard !isReported, state == .dismissed || state == .ended else { continue }
                isReported = true
                self?.reportRemoval(of: activity.id)
            }
            #if DEBUG
            Self.logEndOfStateUpdates(of: activity.id)
            #endif
        }
    }

    private func reportRemoval(of id: String) {
        let endedByTheApp = idsEndedByTheApp.withLock { $0.contains(id) }
        onRemoval?(
            LiveActivityRemoval(
                endedByTheApp: endedByTheApp,
                activitiesAreEnabled: ActivityAuthorizationInfo().areActivitiesEnabled
            )
        )
    }
}

extension ActivityKitStationLiveActivityClient: LiveActivityRemovalWatcher {
    func watchRemovals(_ onRemoval: @escaping @MainActor (LiveActivityRemoval) -> Void) {
        self.onRemoval = onRemoval
    }
}
