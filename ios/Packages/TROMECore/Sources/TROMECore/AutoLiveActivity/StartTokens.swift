import Foundation

/// The push-to-start token of the silent start: the one that iOS gave this process, or else the last one that iOS gave
/// the app, kept on the phone. A process that iOS wakes at a station may get no token in its few seconds; on a walk of
/// 2026-10-31, no ask reached the server all day. So the ask takes the kept token at once rather than wait: the server
/// needs most of the 10 seconds, and a token that iOS no longer knows comes back as a refusal, which forgets it.
/// The app gives it each token that iOS gives (`receive`); the times in the Wake log count from `launchedAt`.
@MainActor
public final class StartTokens: PushToStartTokenSource {
    private var given: String?
    private var kept: String?
    private var waiting: [UUID: CheckedContinuation<StartToken?, Never>] = [:]
    private let store: StartTokenStore
    private let wakeLog: WakeLog?
    private let launchedAt: Date
    private let now: @Sendable () -> Date

    /// `tokenAtLaunch` is the token that iOS already held when the app launched, if any.
    public init(
        storage: any KeyValueStore,
        tokenAtLaunch: String?,
        wakeLog: WakeLog?,
        launchedAt: Date,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        store = StartTokenStore(storage: storage)
        self.wakeLog = wakeLog
        self.launchedAt = launchedAt
        self.now = now
        kept = store.load()
        let atLaunch = tokenAtLaunch == nil ? "none" : "yes"
        wakeLog?.record(.silentStart, "Start token at launch: \(atLaunch); kept: \(kept == nil ? "none" : "yes")")
        if let tokenAtLaunch {
            take(tokenAtLaunch)
        }
    }

    public func startToken() async -> StartToken? {
        if let given {
            return StartToken(value: given, isKept: false)
        }
        if let kept {
            return StartToken(value: kept, isKept: true)
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

    public func forget(_ token: String) {
        if given == token {
            given = nil
        }
        if kept == token {
            kept = nil
            store.save(nil)
        }
    }

    /// A token that iOS gives this process: it replaces the kept one.
    public func receive(_ token: String) {
        let seconds = String(format: "%.1f", now().timeIntervalSince(launchedAt))
        let which = token == kept ? "the kept one" : "new"
        wakeLog?.record(.silentStart, "iOS gave a start token, \(seconds) s after launch (\(which))")
        take(token)
    }

    private func take(_ token: String) {
        given = token
        if kept != token {
            kept = token
            store.save(token)
        }
        let continuations = waiting.values
        waiting = [:]
        continuations.forEach { $0.resume(returning: StartToken(value: token, isKept: false)) }
    }
}
