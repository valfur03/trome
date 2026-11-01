#if SILENT_START
import ActivityKit
import Foundation
import TROMECore
import UIKit

/// The push-to-start token of the station Live Activity, asked for at every launch, a background launch by the area
/// of a station included. It follows Apple's advice for the token: register the app with Apple's push service at
/// launch, read the token that iOS already holds, and listen to `pushToStartTokenUpdates` at once, for the whole run.
/// The registration comes first, in the same task as the listening, as in a test app that did get a token on an
/// iPhone; it asks the rider for nothing, and its device token goes nowhere (`PushRegistrationAppDelegate`).
/// It runs in every build with the silent start, with no server too, so that a desk build can show the token lines.
@MainActor
enum ActivityKitStartTokens {
    static func listen(wakeLog: WakeLog?) -> StartTokens {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        wakeLog?.record(.silentStart, "Live Activities enabled: \(enabled ? "yes" : "no")")
        let tokens = StartTokens(
            storage: UserDefaults.standard,
            tokenAtLaunch: Activity<StationActivityAttributes>.pushToStartToken.map(hex),
            wakeLog: wakeLog,
            launchedAt: Date()
        )
        PushRegistrationAppDelegate.logAnswers(to: wakeLog)
        Task {
            UIApplication.shared.registerForRemoteNotifications()
            wakeLog?.record(.silentStart, "Push registration asked")
            for await data in Activity<StationActivityAttributes>.pushToStartTokenUpdates {
                tokens.receive(hex(data))
            }
        }
        return tokens
    }

    private nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
