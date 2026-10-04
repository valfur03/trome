import Foundation
import Synchronization

final class ServerRetrySchedule: Sendable {
    private let waits = Mutex<[String: ServerOutAnswer]>([:])

    func error(waitingFor monitoringRef: String, now: Date) -> NextTrainsError? {
        waits.withLock { waits in
            guard let answer = waits[monitoringRef], now < answer.retryAt else { return nil }
            return answer.error
        }
    }

    func wait(for answer: ServerOutAnswer, at monitoringRef: String) {
        waits.withLock { $0[monitoringRef] = answer }
    }

    func forget(_ monitoringRef: String) {
        _ = waits.withLock { $0.removeValue(forKey: monitoringRef) }
    }
}
