import Foundation
@testable import TROMECore

/// The start of the Live Activity in a recorded set of promises, its key `liveActivityStart`: the request that the
/// builds of the set send to start the Live Activity of a station, and how they read each answer.
/// The server check reads the same key (`server/test/cloudflare/start-promises.ts`).
struct LiveActivityStartPromise: Decodable {
    struct App: Decodable {
        let waitForTheAnswerSeconds: TimeInterval
    }

    struct Request: Decodable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: [String: String]
    }

    struct Station: Decodable {
        let station: String
        let shape: String
    }

    struct StartToken: Decodable {
        let startToken: String
        let shape: String
    }

    let app: App
    let request: Request
    let stations: [Station]
    let startTokens: [StartToken]
    let answers: [PromisedAnswer]

    /// The station and start token of each ask that the answer names.
    func asks(for answer: PromisedAnswer) throws -> [(station: String, startToken: String)] {
        switch answer.askFor {
        case "every station and start token":
            stations.flatMap { station in startTokens.map { (station.station, $0.startToken) } }
        case "the first station":
            Array(zip(stations.prefix(1).map(\.station), startTokens.prefix(1).map(\.startToken)))
        default:
            throw BuildPromiseSetError.unknown("the stations of \"\(answer.askFor)\"")
        }
    }
}

/// How the builds read an answer to the start: the Live Activity comes, or nothing (1.0.0 (4) sends its arrival
/// notification instead); from 1.0.0 (5), a refusal can also make the build drop its start token.
enum PromisedStartReading: Equatable {
    case start
    /// No start, from the status alone: the set judges no body, so the build may read one either way.
    case noStart
    /// No start, and the build keeps its start token: the body has no reason that names the token.
    case noStartKeepingTheToken
    /// No start, and the build drops the start token: the server relays a reason of Apple that names the token.
    case noStartDroppingTheToken
}

extension PromisedAnswer {
    /// How the builds read this answer to the start, from the shape of the promise, as the words of its `reads` say:
    /// status 200 with a result of `oneOf` is the start; status 502 with the result `refused` and a reason of `oneOf`
    /// drops the token; any status out of 2xx is no start, which keeps the token when the body promises a reason
    /// of `noneOf` alone.
    func startReading() throws -> PromisedStartReading {
        let json = body.json
        if status.exact == 200, json?["result"]?.oneOf?.isEmpty == false {
            return .start
        }
        if status.exact == 502, json?["result"]?.exact == .text("refused"), json?["reason"]?.oneOf?.isEmpty == false {
            return .noStartDroppingTheToken
        }
        if status.notClass == "2xx", body.primAnswer != true {
            guard let json else { return .noStart }
            let reason = json["reason"]
            if json.keys.sorted() == ["reason"], reason?.noneOf?.isEmpty == false, reason?.oneOf == nil {
                return .noStartKeepingTheToken
            }
        }
        throw BuildPromiseSetError.unknown("how the builds read the start answer \"\(when)\"")
    }
}
