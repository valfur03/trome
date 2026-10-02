import ActivityKit
import RATPCore

@MainActor
final class ActivityKitStationLiveActivityClient: StationLiveActivityClient {
    private nonisolated static var runningActivities: [Activity<StationActivityAttributes>] {
        Activity<StationActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    init() {
        #if DEBUG
        Self.logStatesFromLaunch()
        #endif
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
        #if DEBUG
        Self.log(content, sentBy: "start")
        #endif
        _ = try Activity.request(
            attributes: StationActivityAttributes(),
            content: ActivityContent(state: content, staleDate: content.staleDate),
            pushType: nil
        )
    }

    nonisolated func update(_ content: StationActivityAttributes.ContentState) async {
        #if DEBUG
        Self.log(content, sentBy: "update")
        #endif
        for activity in Self.runningActivities {
            await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
        }
    }

    nonisolated func end() async {
        #if DEBUG
        Self.logEnd(of: Activity<StationActivityAttributes>.activities)
        #endif
        for activity in Activity<StationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
