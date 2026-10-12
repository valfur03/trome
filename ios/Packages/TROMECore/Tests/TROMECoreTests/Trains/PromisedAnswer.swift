import Foundation
@testable import TROMECore

/// One answer of a recorded set of promises: when the server gives it, its status, headers and body as matchers,
/// and how the builds of the set read it.
struct PromisedAnswer: Decodable {
    struct RetryTime: Decodable {
        let header: String
        let headerForm: String
        let orBodyKey: String
        let bodyKeyForm: String
    }

    struct Body: Decodable {
        let primAnswer: Bool?
        let json: [String: Matcher]?
    }

    let when: String
    let askFor: String
    let prim: String?
    let requestHeaders: [String: String]?
    let status: PromisedStatus
    let headers: [String: Matcher]?
    let retryTime: RetryTime?
    let body: Body

    /// How the builds read this answer, from the shape of the promise, as the words of its `reads` say:
    /// the PRIM answer with a 2xx status is the times; a body `"status": "out"` with a retry time is the server out
    /// for the reasons that `oneOf` names, and a failure of the stop for the reasons that `noneOf` leaves;
    /// the answer to a token that the server does not accept is the refusal.
    func reading() throws -> PromisedReading {
        let json = body.json ?? [:]
        if requestHeaders != nil, body.primAnswer != true {
            return .refusal
        }
        if body.primAnswer == true, status.class == "2xx" {
            return .times
        }
        if json["status"]?.exact == .text("out"), retryTime != nil, let reason = json["reason"] {
            if reason.oneOf != nil {
                return .out
            }
            if reason.noneOf != nil {
                return .failure
            }
        }
        throw BuildPromiseSetError.unknown("how the builds read the answer \"\(when)\"")
    }

    func stops(of set: BuildPromiseSet) throws -> [BuildPromiseSet.Stop] {
        switch askFor {
        case "every stop": set.stops
        case "the first stop": Array(set.stops.prefix(1))
        default: throw BuildPromiseSetError.unknown("the stops of \"\(askFor)\"")
        }
    }
}

/// The status of a promised answer: one status, a class ("2xx"), or any status out of a class.
struct PromisedStatus: Decodable {
    let `class`: String?
    let notClass: String?
    let exact: Int?

    private enum CodingKeys: String, CodingKey {
        case `class`, notClass
        case exact = "is"
    }
}

enum PromisedReading: Equatable {
    case times
    case out
    case failure
    case refusal
}

/// What a promised value may be, as `build-promises.ts` judges it.
struct Matcher: Decodable {
    enum Value: Decodable, Equatable {
        case text(String)
        case number(Double)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }

        var json: Any {
            switch self {
            case .text(let text): text
            case .number(let number): number
            }
        }
    }

    let exact: Value?
    let form: String?
    let oneOf: [String]?
    let noneOf: [String]?
    let type: String?
    let optional: Bool?

    private enum CodingKeys: String, CodingKey {
        case form, oneOf, noneOf, type, optional
        case exact = "is"
    }

    /// Whether the server may give this value, as the server check judges it.
    func allows(_ value: Value) -> Bool {
        if let exact, value != exact { return false }
        guard case .text(let text) = value else { return type == nil && oneOf == nil && form == nil }
        if let oneOf, !oneOf.contains(text) { return false }
        if let noneOf, noneOf.contains(text) { return false }
        return form.map { Self.text(text, isIn: $0) } ?? true
    }

    static func text(_ text: String, isIn form: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: form) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
