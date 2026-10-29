#if SILENT_START
import ActivityKit
import Foundation
import TROMECore

/// The push-to-start token of the station Live Activity. ActivityKit makes it only for an app that listens to
/// `pushToStartTokenUpdates`, so the source listens from the launch; a woken app then has it at the arrival.
@MainActor
final class ActivityKitPushToStartTokenSource: PushToStartTokenSource {
    private var token: String?
    private var waiting: [UUID: CheckedContinuation<String?, Never>] = [:]
    private let wakeLog: WakeLog?

    init(wakeLog: WakeLog?) {
        self.wakeLog = wakeLog
        token = Activity<StationActivityAttributes>.pushToStartToken.map(Self.hex)
        Task { [weak self] in
            for await data in Activity<StationActivityAttributes>.pushToStartTokenUpdates {
                self?.receive(Self.hex(data))
            }
        }
    }

    func startToken() async -> String? {
        if let token {
            return token
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                waiting[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiting.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    private func receive(_ newToken: String) {
        if token == nil {
            wakeLog?.record(.silentStart, "iOS gave a start token")
        }
        token = newToken
        let continuations = waiting.values
        waiting = [:]
        continuations.forEach { $0.resume(returning: newToken) }
    }

    private nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
