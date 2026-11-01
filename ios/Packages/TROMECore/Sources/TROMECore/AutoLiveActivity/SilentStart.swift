import Foundation

/// The push-to-start token of the Live Activity, which ActivityKit gives the app (iOS 17.2 and later).
@MainActor
public protocol PushToStartTokenSource: AnyObject {
    /// The token to ask with, in hexadecimal; when there is none yet, waits for the first one that iOS gives, and
    /// gives nil when the wait is cancelled.
    func startToken() async -> StartToken?
    /// Drops a token that the server refused as invalid, so that no later ask uses it again.
    func forget(_ token: String)
}

/// A push-to-start token, and whether it is the one kept from an earlier process, not one that iOS gave this one.
public struct StartToken: Equatable, Sendable {
    public let value: String
    public let isKept: Bool
}

/// Asks for the start of the Live Activity of a station on this iPhone, with its push-to-start token.
public protocol LiveActivityStarter: Sendable {
    func start(stationId: String, startToken: String) async -> LiveActivityStartAnswer
}

/// The silent start: when iOS wakes the app at a station, the server starts the Live Activity through Apple's push
/// service, so that the rider finds it on the lock screen with no notification and no tap.
/// Nothing comes when the app has no start token, when the answer is not one of the two that start it, or when no
/// answer comes within `answerLimit` (a woken app has only seconds to run): the wake log then says why.
@MainActor
public final class SilentStart {
    public nonisolated static let answerLimit: Duration = .seconds(10)
    /// The seconds past the limit that a running app may take to end the ask, before the record says it was suspended.
    nonisolated static let suspensionTolerance: Int64 = 1

    enum Outcome: Equatable {
        case answered(LiveActivityStartAnswer)
        case noStartToken
        case noAnswerInTime

        var startsTheLiveActivity: Bool {
            guard case .answered(let answer) = self else { return false }
            return answer.startsTheLiveActivity
        }

        /// Why the Live Activity did not come, in the words of the answer lines, with how long the ask lasted: a
        /// process that iOS suspended during the ask runs no timer, so an ask that lasts past its limit tells a walk
        /// that iOS suspended the app.
        func cause(lasting seconds: Int) -> String {
            let limit = SilentStart.answerLimit.components.seconds
            let outcome = switch self {
            case .answered(let answer): "\(answer.summary), after \(seconds) s"
            case .noStartToken: "No start token from iOS within \(limit) s"
            case .noAnswerInTime: "No answer within \(limit) s"
            }
            guard Int64(seconds) > limit + SilentStart.suspensionTolerance else { return outcome }
            return "\(outcome); the ask lasted \(seconds) s for a limit of \(limit) s: iOS suspended the app"
        }
    }

    /// The outcome of one ask, and how long it lasted.
    struct Ask: Equatable {
        let outcome: Outcome
        let seconds: Int

        var startsTheLiveActivity: Bool { outcome.startsTheLiveActivity }

        var cause: String { outcome.cause(lasting: seconds) }
    }

    private let starter: any LiveActivityStarter
    private let tokens: any PushToStartTokenSource
    private let wakeLog: WakeLog?
    private let backgroundTimeRemaining: (@MainActor () -> TimeInterval)?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `backgroundTimeRemaining` reads the background time that iOS still gives the app, for the record.
    public init(
        starter: any LiveActivityStarter,
        tokens: any PushToStartTokenSource,
        wakeLog: WakeLog? = nil,
        backgroundTimeRemaining: (@MainActor () -> TimeInterval)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.starter = starter
        self.tokens = tokens
        self.wakeLog = wakeLog
        self.backgroundTimeRemaining = backgroundTimeRemaining
        self.now = now
        self.sleep = sleep
    }

    /// Asks the server once for the start of the Live Activity of the station. Only a start writes its answer
    /// line: the caller writes the line of a start that does not come, with its cause.
    func start(at station: Station) async -> Ask {
        let time = backgroundTimeRemaining.map { " (\(BackgroundTime.line(remaining: $0())))" } ?? ""
        wakeLog?.record(.silentStart, "Asks the server to start the Live Activity: \(station.name)\(time)")
        let askedAt = now()
        let progress = Progress()
        let outcome = await askWithinTheLimit(station, progress)
            ?? (progress.hasStartToken ? .noAnswerInTime : .noStartToken)
        let ask = Ask(outcome: outcome, seconds: Int(now().timeIntervalSince(askedAt).rounded()))
        if ask.startsTheLiveActivity {
            wakeLog?.record(.silentStart, "Answer: \(ask.cause)")
        }
        return ask
    }

    /// The outcome of the ask, or nil when the time is over first: the late ask is then cancelled, and its outcome
    /// lost. Both run as child tasks, so a cancellation of the caller also ends the wait.
    private func askWithinTheLimit(_ station: Station, _ progress: Progress) async -> Outcome? {
        let sleep = sleep
        return await withTaskGroup(of: Outcome?.self, returning: Outcome?.self) { group in
            group.addTask {
                await self.ask(station, progress)
            }
            group.addTask {
                try? await sleep(Self.answerLimit)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap { $0 }
        }
    }

    private func ask(_ station: Station, _ progress: Progress) async -> Outcome {
        guard let token = await tokens.startToken() else { return .noStartToken }
        progress.hasStartToken = true
        let which = token.isKept ? "the kept start token" : "this launch's start token"
        wakeLog?.record(.silentStart, "Asks with \(which)")
        let answer = await starter.start(stationId: station.id, startToken: token.value)
        if answer.refusesTheStartToken {
            tokens.forget(token.value)
            wakeLog?.record(.silentStart, "Start token refused as invalid: forgotten")
        }
        return .answered(answer)
    }
}

@MainActor
private final class Progress {
    var hasStartToken = false
}
