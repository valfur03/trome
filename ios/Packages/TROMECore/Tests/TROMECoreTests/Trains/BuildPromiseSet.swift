import Foundation
@testable import TROMECore

/// A recorded set of promises, `contracts/builds/<set>/promises.json`: what the builds of the set send to the server
/// of the app, and how they read each answer.
/// The server check reads the same file (`server/test/cloudflare/build-promises.ts`), and knows the same keys:
/// a key that this reader does not know fails, so that a new kind of promise is taught here, never skipped.
struct BuildPromiseSet: Decodable {
    struct App: Decodable {
        let waitForOneAnswerSeconds: TimeInterval
        let askEverySeconds: TimeInterval
        let shortestWaitAfterAnOutAnswerSeconds: TimeInterval
    }

    struct Request: Decodable {
        let method: String
        let path: String
        let headers: [String: String]
    }

    struct Stop: Decodable {
        let stop: String
        let shape: String
        let prim: String
    }

    let builds: [String]
    let app: App
    let request: Request
    let stops: [Stop]
    let answers: [PromisedAnswer]
    private(set) var folder = URL(filePath: "/")

    private enum CodingKeys: String, CodingKey {
        case builds, app, request, stops, answers
    }

    static let knownKeys: [String: Set<String>] = [
        "set": ["description", "builds", "app", "request", "stops", "answers"],
        "app": ["waitForOneAnswerSeconds", "askEverySeconds", "shortestWaitAfterAnOutAnswerSeconds"],
        "request": ["method", "path", "headers"],
        "stop": ["stop", "shape", "prim"],
        "answer": ["when", "askFor", "reads", "prim", "requestHeaders", "status", "headers", "retryTime", "body"],
        "status": ["class", "notClass", "is"],
        "retryTime": ["header", "headerForm", "orBodyKey", "bodyKeyForm"],
        "body": ["primAnswer", "json"],
        "matcher": ["is", "form", "oneOf", "noneOf", "type", "optional"]
    ]

    /// The set of the newest build that riders may hold: the next upload copies it, and the app code must still
    /// send and read as it says.
    /// Only the builds of the other sets are read: they never change, so this reader may need keys that they lack.
    static func newest() throws -> BuildPromiseSet {
        let folders = try Fixture.buildPromiseSetFolders().map { folder in
            let data = try Data(contentsOf: folder.appending(path: "promises.json"))
            return (folder: folder, newestBuild: try JSONDecoder().decode(Builds.self, from: data).newestBuild)
        }
        guard let newest = folders.max(by: { $0.newestBuild < $1.newestBuild }) else {
            throw BuildPromiseSetError.noSet
        }
        return try read(newest.folder)
    }

    private struct Builds: Decodable {
        let builds: [String]

        var newestBuild: BuildNumber {
            BuildNumber.newest(of: builds)
        }
    }

    static func read(_ folder: URL) throws -> BuildPromiseSet {
        let data = try Data(contentsOf: folder.appending(path: "promises.json"))
        let unknown = unknownKeys(in: try JSONSerialization.jsonObject(with: data))
        guard unknown.isEmpty else {
            throw BuildPromiseSetError.unknownKeys(folder.lastPathComponent, unknown)
        }
        var set = try JSONDecoder().decode(BuildPromiseSet.self, from: data)
        set.folder = folder
        return set
    }

    var name: String {
        folder.lastPathComponent
    }

    func data(of file: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: file))
    }

    func requestHeader(_ value: String) -> String {
        value.replacingOccurrences(of: "<APP_TOKEN>", with: TrainServerConfiguration.test.appToken)
    }

    private static func unknownKeys(in set: Any) -> [String] {
        let set = set as? [String: Any] ?? [:]
        let answers = set["answers"] as? [[String: Any]] ?? []
        var objects: [(kind: String, object: Any?)] = [("set", set), ("app", set["app"]), ("request", set["request"])]
        objects += (set["stops"] as? [Any] ?? []).map { ("stop", $0) }
        for answer in answers {
            objects += [("answer", answer), ("status", answer["status"]), ("body", answer["body"])]
            objects += answer["retryTime"].map { [("retryTime", $0)] } ?? []
            let matchers = Array((answer["headers"] as? [String: Any] ?? [:]).values)
                + Array(((answer["body"] as? [String: Any])?["json"] as? [String: Any] ?? [:]).values)
            objects += matchers.map { ("matcher", $0) }
        }
        return objects.flatMap { kind, object in
            let keys = (object as? [String: Any]).map { Set($0.keys) } ?? []
            return keys.subtracting(knownKeys[kind] ?? []).sorted().map { "\(kind).\($0)" }
        }
    }
}

/// A build as the table of the release guide names it, "1.0.0 (3)": the newest has the highest version, then the
/// highest build number.
struct BuildNumber: Comparable {
    let version: [Int]
    let build: Int

    init(version: [Int], build: Int) {
        self.version = version
        self.build = build
    }

    init?(_ text: String) {
        let parts = text.split(separator: " ")
        guard parts.count == 2, parts[1].hasPrefix("("), parts[1].hasSuffix(")"),
              let build = Int(parts[1].dropFirst().dropLast())
        else {
            return nil
        }
        let version = parts[0].split(separator: ".").compactMap { Int($0) }
        guard !version.isEmpty, version.count == parts[0].split(separator: ".").count else { return nil }
        self.init(version: version, build: build)
    }

    static func newest(of builds: [String]) -> BuildNumber {
        builds.compactMap(BuildNumber.init).max() ?? BuildNumber(version: [], build: 0)
    }

    static func < (lhs: BuildNumber, rhs: BuildNumber) -> Bool {
        let length = max(lhs.version.count, rhs.version.count)
        let left = lhs.version + Array(repeating: 0, count: length - lhs.version.count)
        let right = rhs.version + Array(repeating: 0, count: length - rhs.version.count)
        return left == right ? lhs.build < rhs.build : left.lexicographicallyPrecedes(right)
    }
}

enum BuildPromiseSetError: Error, CustomStringConvertible {
    case noSet
    case unknownKeys(String, [String])
    case unknown(String)

    var description: String {
        switch self {
        case .noSet:
            "contracts/builds/ has no recorded set of promises"
        case .unknownKeys(let set, let keys):
            "the set \(set) has keys that this test does not know: \(keys.joined(separator: ", ")); "
                + "teach BuildPromiseSet how the app reads them"
        case .unknown(let what):
            "this test does not know \(what): teach it in PromisedAnswer+Replies.swift"
        }
    }
}
