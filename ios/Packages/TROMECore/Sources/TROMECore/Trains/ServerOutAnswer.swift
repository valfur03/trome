import Foundation

struct ServerOutAnswer: Equatable, Sendable {
    static let minimumWait: TimeInterval = 30
    static let reasonsOfAnEmptyBudget: Set<String> = ["budget", "prim-limit"]

    let reason: String
    let retryAt: Date

    private struct Body: Decodable {
        let status: String
        let reason: String?
        let retryAt: String?
    }

    init(reason: String, retryAt: Date) {
        self.reason = reason
        self.retryAt = retryAt
    }

    init?(response: HTTPURLResponse?, body: Data, now: Date) {
        guard let response, !(200..<300).contains(response.statusCode),
              let body = try? JSONDecoder().decode(Body.self, from: body), body.status == "out"
        else {
            return nil
        }
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            .map { now.addingTimeInterval($0) }
        guard let retryAt = retryAfter ?? body.retryAt.flatMap(SIRIDate.parse) else { return nil }
        self.reason = body.reason ?? ""
        self.retryAt = max(retryAt, now.addingTimeInterval(Self.minimumWait))
    }

    var error: NextTrainsError {
        Self.reasonsOfAnEmptyBudget.contains(reason) ? .serverOut(retryAt: retryAt) : .serviceFailure
    }
}
