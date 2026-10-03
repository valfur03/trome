#if DEBUG
import ActivityKit
import os
import TROMECore

extension ActivityKitStationLiveActivityClient {
    nonisolated private static let stateLogger = Logger(category: "LiveActivity")

    static func logLaunch(_ found: [Activity<StationActivityAttributes>]) {
        let listed = list(found)
        stateLogger.notice("launch: \(found.count, privacy: .public) Live Activities [\(listed, privacy: .public)]")
    }

    nonisolated static func logEnd(of activities: [Activity<StationActivityAttributes>]) {
        let listed = list(activities)
        let count = activities.count
        stateLogger.notice("the app ends \(count, privacy: .public) Live Activities [\(listed, privacy: .public)]")
    }

    static func logFollowed(_ activity: Activity<StationActivityAttributes>) {
        let id = activity.id
        let state = describe(activity.activityState)
        stateLogger.notice("\(id, privacy: .public): followed, state \(state, privacy: .public)")
    }

    static func log(_ state: ActivityState, of id: String) {
        stateLogger.notice("\(id, privacy: .public): state update \(describe(state), privacy: .public)")
    }

    static func logEndOfStateUpdates(of id: String) {
        stateLogger.notice("\(id, privacy: .public): state updates ended")
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
#endif
