import ActivityKit
import RATPCore

@MainActor
final class ActivityKitStationLiveActivityClient: StationLiveActivityClient {
    private nonisolated static var runningActivities: [Activity<StationActivityAttributes>] {
        Activity<StationActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    var isShowing: Bool {
        !Self.runningActivities.isEmpty
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
    }

    nonisolated func update(_ content: StationActivityAttributes.ContentState) async {
        for activity in Self.runningActivities {
            await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
        }
    }

    nonisolated func end() async {
        for activity in Activity<StationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
