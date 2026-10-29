import Foundation

/// The push-to-start token of the Live Activity, which ActivityKit gives the app (iOS 17.2 and later).
@MainActor
public protocol PushToStartTokenSource: AnyObject {
    /// The latest token, in hexadecimal; when iOS has given none yet, waits for the first one, and gives nil when
    /// the wait is cancelled.
    func startToken() async -> String?
}

/// Asks for the start of the Live Activity of a station on this iPhone, with its push-to-start token.
public protocol LiveActivityStarter: Sendable {
    func start(stationId: String, startToken: String) async -> LiveActivityStartAnswer
}

/// The silent start: when iOS wakes the app at a station, the server starts the Live Activity through Apple's push
/// service, so that the rider finds it on the lock screen with no notification and no tap.
/// The app falls back to its arrival notification when it has no start token, when the answer is not one of the two
/// that start it, or when no answer comes within `answerLimit`: a woken app has only seconds to run.
@MainActor
public final class SilentStart {
    public nonisolated static let answerLimit: Duration = .seconds(10)

    enum Outcome: Equatable {
        case answered(LiveActivityStartAnswer)
        case noStartToken
        case noAnswerInTime

        var startsTheLiveActivity: Bool {
            guard case .answered(let answer) = self else { return false }
            return answer.startsTheLiveActivity
        }

        var line: String {
            let limit = SilentStart.answerLimit.components.seconds
            return switch self {
            case .answered(let answer): "Answer: \(answer.summary)"
            case .noStartToken: "No start token from iOS within \(limit) s"
            case .noAnswerInTime: "No answer within \(limit) s"
            }
        }
    }

    private let starter: any LiveActivityStarter
    private let tokens: any PushToStartTokenSource
    private let wakeLog: WakeLog?
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        starter: any LiveActivityStarter,
        tokens: any PushToStartTokenSource,
        wakeLog: WakeLog? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.starter = starter
        self.tokens = tokens
        self.wakeLog = wakeLog
        self.sleep = sleep
    }

    /// Asks the server once for the start of the Live Activity of the station; true when it comes.
    func start(at station: Station) async -> Bool {
        wakeLog?.record(.silentStart, "Asks the server to start the Live Activity: \(station.name)")
        let progress = Progress()
        let outcome = await askWithinTheLimit(station, progress)
            ?? (progress.hasStartToken ? .noAnswerInTime : .noStartToken)
        wakeLog?.record(.silentStart, outcome.line)
        return outcome.startsTheLiveActivity
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
        return .answered(await starter.start(stationId: station.id, startToken: token))
    }
}

@MainActor
private final class Progress {
    var hasStartToken = false
}
