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

/// How the builds read an answer to the start: the Live Activity comes, or the arrival notification instead.
enum PromisedStartReading: Equatable {
    case start
    case fallback
}

extension PromisedAnswer {
    /// How the builds read this answer to the start, from the shape of the promise, as the words of its `reads` say:
    /// status 200 with a result of `oneOf` is the start; any status out of 2xx, with no promised body, is the fallback.
    func startReading() throws -> PromisedStartReading {
        if status.exact == 200, body.json?["result"]?.oneOf?.isEmpty == false {
            return .start
        }
        if status.notClass == "2xx", body.json == nil, body.primAnswer != true {
            return .fallback
        }
        throw BuildPromiseSetError.unknown("how the builds read the start answer \"\(when)\"")
    }
}
