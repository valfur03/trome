#if DEBUG
import ActivityKit
import os
import RATPCore

extension ActivityKitStationLiveActivityClient {
    nonisolated private static let stateLogger = Logger(subsystem: "RATPActivity", category: "LiveActivity")

    static func logStatesFromLaunch() {
        let found = Activity<StationActivityAttributes>.activities
        let listed = list(found)
        stateLogger.notice("launch: \(found.count, privacy: .public) Live Activities [\(listed, privacy: .public)]")
        let followed = FollowedActivities()
        for activity in found {
            follow(activity, in: followed)
        }
        Task { @MainActor in
            for await activity in Activity<StationActivityAttributes>.activityUpdates {
                follow(activity, in: followed)
            }
        }
    }

    nonisolated static func logEnd(of activities: [Activity<StationActivityAttributes>]) {
        let listed = list(activities)
        let count = activities.count
        stateLogger.notice("the app ends \(count, privacy: .public) Live Activities [\(listed, privacy: .public)]")
    }

    private static func follow(_ activity: Activity<StationActivityAttributes>, in followed: FollowedActivities) {
        guard followed.insert(activity.id) else { return }
        let id = activity.id
        let state = describe(activity.activityState)
        stateLogger.notice("\(id, privacy: .public): followed, state \(state, privacy: .public)")
        Task { @MainActor in
            for await state in activity.activityStateUpdates {
                stateLogger.notice("\(id, privacy: .public): state update \(describe(state), privacy: .public)")
            }
            stateLogger.notice("\(id, privacy: .public): state updates ended")
        }
    }

    nonisolated private static func list(_ activities: [Activity<StationActivityAttributes>]) -> String {
        activities.map { "\($0.id) \(describe($0.activityState))" }.joined(separator: ", ")
    }

    nonisolated private static func describe(_ state: ActivityState) -> String {
        switch state {
        case .active: "active"
        case .ended: "ended"
        case .dismissed: "dismissed"
        case .stale: "stale"
        case .pending: "pending"
        @unknown default: "unknown"
        }
    }
}

@MainActor
private final class FollowedActivities {
    private var ids: Set<String> = []

    func insert(_ id: String) -> Bool {
        ids.insert(id).inserted
    }
}
#endif
