import Foundation
import Synchronization
@testable import TROMECore

/// The server of the start route: it answers each ask with `answer`, or holds it while `answer` is nil,
/// until the test gives one or the ask is cancelled.
final class StubLiveActivityStarter: LiveActivityStarter {
    struct Ask: Equatable, Sendable {
        let stationId: String
        let startToken: String
    }

    private let answer: Mutex<LiveActivityStartAnswer?>
    private let recorded = Mutex<[Ask]>([])

    init(answer: LiveActivityStartAnswer?) {
        self.answer = Mutex(answer)
    }

    var asks: [Ask] {
        recorded.withLock { $0 }
    }

    func answer(with answer: LiveActivityStartAnswer) {
        self.answer.withLock { $0 = answer }
    }

    func start(stationId: String, startToken: String) async -> LiveActivityStartAnswer {
        recorded.withLock { $0.append(Ask(stationId: stationId, startToken: startToken)) }
        while !Task.isCancelled {
            if let answer = answer.withLock({ $0 }) {
                return answer
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return .noAnswer
    }
}

/// The push-to-start token of ActivityKit: with no token, it waits until the wait is cancelled, as iOS may never
/// give one.
@MainActor
final class StubStartTokens: PushToStartTokenSource {
    static let token = "0123456789abcdef0123456789abcdef"

    var token: String? = StubStartTokens.token

    func startToken() async -> String? {
        if let token {
            return token
        }
        try? await Task.sleep(for: .seconds(3_600))
        return nil
    }
}
