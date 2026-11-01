#if SILENT_START
import Foundation
import TROMECore
import UIKit

/// Receives the answer of iOS to the registration with Apple's push service (`ActivityKitStartTokens`), which comes to
/// the app delegate only, and passes it to the Wake log. The device token itself is not kept and goes nowhere: the
/// silent start uses the push-to-start token of ActivityKit.
final class PushRegistrationAppDelegate: NSObject, UIApplicationDelegate {
    private static let answered = Notification.Name("PushRegistrationAppDelegate.answered")
    private static let answerKey = "answer"

    /// Writes each answer in the Wake log: "accepted", or the error of iOS.
    @MainActor
    static func logAnswers(to wakeLog: WakeLog?) {
        _ = NotificationCenter.default.addObserver(forName: answered, object: nil, queue: .main) { note in
            let answer = note.userInfo?[answerKey] as? String ?? "unknown"
            MainActor.assumeIsolated {
                wakeLog?.record(.silentStart, "Push registration: \(answer)")
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Self.post("accepted")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Self.post("failed, \(error.localizedDescription)")
    }

    private static func post(_ answer: String) {
        NotificationCenter.default.post(name: answered, object: nil, userInfo: [answerKey: answer])
    }
}
#endif
