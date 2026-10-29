import Foundation

/// The answer of the server to the start of a Live Activity, `POST /v1/stations/{stationId}/live-activity`
/// (the examples are in `contracts/api/`). Only the first two mean that the Live Activity comes:
/// from every other one, the app falls back to its arrival notification.
public enum LiveActivityStartAnswer: Equatable, Sendable {
    /// Apple took the start.
    case started
    /// The same start token asked for the same station less than 45 minutes ago: the server sent nothing again.
    case alreadyStarted
    /// Apple refused the start, did not answer (`no-answer`), the server failed, or the answer is not one
    /// that the app knows (the reason then gives the status).
    case refused(reason: String)
    /// The server has no key of Apple's push service.
    case notSetUp
    /// The request failed before any answer: no network, or no server at the host.
    case noAnswer

    var startsTheLiveActivity: Bool {
        self == .started || self == .alreadyStarted
    }

    init(status: Int, body: Data) {
        let read = try? JSONDecoder().decode(Body.self, from: body)
        switch (status, read?.result) {
        case (200, "started"):
            self = .started
        case (200, "already-started"):
            self = .alreadyStarted
        case (502, "refused"):
            self = .refused(reason: read?.reason ?? "no reason")
        case (503, "not-set-up"):
            self = .notSetUp
        default:
            self = .refused(reason: "HTTP \(status)")
        }
    }

    var summary: String {
        switch self {
        case .started: "started"
        case .alreadyStarted: "already started"
        case .refused(let reason): "refused (\(reason))"
        case .notSetUp: "not set up"
        case .noAnswer: "no answer"
        }
    }

    private struct Body: Decodable {
        let result: String
        let reason: String?
    }
}
