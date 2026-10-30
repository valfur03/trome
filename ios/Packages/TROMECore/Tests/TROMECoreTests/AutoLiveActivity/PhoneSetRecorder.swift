import Foundation
import Testing
@testable import TROMECore

/// Records the phone set of this build in the folder of `PHONE_SET_RECORD` (`make phone-set-record`): the exact bytes
/// that the app writes in `UserDefaults` for each state that a rider can leave on the phone, and the content of the
/// Live Activity of each case of `contracts/live-activity/cases/`, as this build encodes it.
/// `PhoneSetTests` reads every recorded set of `contracts/phone/` with the code of today, as an update does.
///
/// Each state folder holds one file per key of `UserDefaults`, with the bytes that the store of this build wrote, and
/// `rider.json`, what the rider set, written here from plain values and never from the types of the app: so a renamed
/// key or case changes the bytes, never what the test expects.
/// This file uses only code that the first build, 1.0.0 (1), already has: a build older than the recorder is recorded
/// by a copy of this file alone in a checkout of its tag. `PhoneSetRecorder+PushStart.swift` records the states that
/// the newer builds can hold.
/// With no `PHONE_SET_RECORD`, `make test` skips it.
@MainActor
struct PhoneSetRecorder {
    nonisolated static let output = ProcessInfo.processInfo.environment["PHONE_SET_RECORD"]
        .map { URL(filePath: $0, directoryHint: .isDirectory) }

    /// The case of `contracts/live-activity/cases/` whose station and times the states of a shown Live Activity use.
    static let shownCase = "abbesses"
    static let startedBefore: TimeInterval = 5 * 60

    @Test(.enabled(if: output != nil))
    func recordsTheAutomaticModeOfARider() throws {
        let now = try Self.date("2026-10-30T08:00:00Z")
        try record("automatic-on", rider: ["automaticMode": "on"]) { storage in
            _ = automaticMode(in: storage, now: now)
        }
        try record("automatic-off", rider: ["automaticMode": "off"]) { storage in
            automaticMode(in: storage, now: now).setOn(false)
        }
        let until = now.addingTimeInterval(60 * 60)
        try record("automatic-snoozed", rider: ["automaticMode": "snoozed", "snoozedUntil": Self.text(until)]) { storage in
            automaticMode(in: storage, now: now).snooze(for: .oneHour)
        }
    }

    @Test(.enabled(if: output != nil))
    func recordsWhatTheLiveActivityFollows() async throws {
        let shown = try await Self.trains(of: Self.shownCase)
        let station = shown.station
        let startedAt = shown.now.addingTimeInterval(-Self.startedBefore)
        let lastTimes = try Self.lastTimes(shown.trains, of: station)
        try record("live-activity-shown", rider: [
            "automaticMode": "on",
            "arrivalStationId": station.id,
            "shown": ["stationId": station.id, "startedAt": Self.text(startedAt), "hasBeenNear": true],
            "lastTimes": lastTimes
        ]) { storage in
            _ = automaticMode(in: storage, now: shown.now)
            var state = AutoLiveActivityState(arrivalStationId: station.id)
            state.shown = .init(stationId: station.id, startedAt: startedAt, hasBeenNear: true)
            AutoLiveActivityStore(storage: storage).save(state)
            StationLiveActivityInputsStore(storage: storage).save(.init(station: station, trains: shown.trains))
        }
        // The rider swiped the Live Activity away, then walked off: only the pause keeps it from coming back.
        let pauseEnd = shown.now.addingTimeInterval(StationPause.duration)
        try record("paused-after-a-swipe", rider: [
            "pause": ["stationId": station.id, "end": Self.text(pauseEnd)]
        ]) { storage in
            let state = AutoLiveActivityState(pause: StationPause(stationId: station.id, end: pauseEnd))
            AutoLiveActivityStore(storage: storage).save(state)
        }
        // The Live Activity ended at its time while the rider stayed at the station: the app does not start it again.
        try record("arrival-station", rider: ["arrivalStationId": station.id]) { storage in
            AutoLiveActivityStore(storage: storage).save(AutoLiveActivityState(arrivalStationId: station.id))
        }
        try record("last-times-no-live-data", rider: ["lastTimes": ["stationId": station.id, "noLiveData": true]]) {
            StationLiveActivityInputsStore(storage: $0).save(.init(station: station, trains: .noLiveData))
        }
    }

    @Test(.enabled(if: output != nil))
    func recordsTheContentOfTheLiveActivityOfEachCase() async throws {
        let folder = try Self.contractsFolder("live-activity/cases")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path())
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
        #expect(!names.isEmpty)
        for name in names {
            let trains = try await Self.trains(of: name)
            let content = StationActivityAttributes.ContentState(
                station: trains.station,
                trains: trains.trains,
                now: trains.now
            )
            try Self.write(JSONEncoder().encode(content), to: "live-activity/\(name).json")
        }
    }

    func automaticMode(in storage: RecordingStore, now: Date) -> AutomaticModeModel {
        AutomaticModeModel(
            store: AutomaticModeStore(storage: storage),
            now: { now },
            sleep: { _ in throw CancellationError() },
            calendar: Calendar(identifier: .gregorian)
        )
    }

    /// Runs `write` on an empty store, then writes each value that it holds, and what the rider set.
    func record(_ state: String, rider: [String: Any], write: (RecordingStore) throws -> Void) throws {
        let storage = RecordingStore()
        try write(storage)
        #expect(!storage.values.isEmpty, "\(state): the app wrote nothing")
        for (key, value) in storage.values {
            try Self.write(value, to: "states/\(state)/\(key).json")
        }
        var text = try JSONSerialization.data(withJSONObject: rider, options: [.prettyPrinted, .sortedKeys])
        text.append(contentsOf: Array("\n".utf8))
        try Self.write(text, to: "states/\(state)/rider.json")
    }
}

extension PhoneSetRecorder {
    /// `UserDefaults` for one state: it keeps the bytes that the app writes.
    final class RecordingStore: KeyValueStore {
        var values: [String: Data] = [:]

        func data(forKey key: String) -> Data? {
            values[key]
        }

        func set(_ value: Any?, forKey key: String) {
            values[key] = value as? Data
        }
    }

    struct Trains {
        let station: Station
        let now: Date
        let trains: NextTrainsState
    }

    /// The next trains of a case, as this build reads the answers of the server for its stops.
    static func trains(of name: String) async throws -> Trains {
        let file = try contractsFolder("live-activity/cases").appending(path: "\(name).json")
        let recordedCase = try JSONDecoder().decode(RecordedCase.self, from: Data(contentsOf: file))
        let station = try #require(StationCatalog.bundled().station(withId: recordedCase.station), "\(name)")
        let now = try date(recordedCase.now)
        let primFolder = try contractsFolder("prim")
        let server = try #require(TrainServerConfiguration(infoDictionary: [
            TrainServerConfiguration.hostKey: "trains.example.com",
            TrainServerConfiguration.appTokenKey: "phone-set-app-token"
        ]))
        let client = CaseHTTPClient(answers: recordedCase.answers, primFolder: primFolder, now: now)
        let model = NextTrainsModel(
            provider: PRIMDeparturesProvider(source: .server(server), httpClient: client, now: { now }),
            catalog: try StationCatalog.bundled(),
            now: { now }
        )
        await model.refresh(for: station)
        return Trains(station: station, now: now, trains: model.state)
    }

    nonisolated static func lastTimes(_ trains: NextTrainsState, of station: Station) throws -> [String: Any] {
        guard case .departures(let board, let updatedAt) = trains else {
            throw RecorderError.noDepartures(station.id)
        }
        return [
            "stationId": station.id,
            "updatedAt": text(updatedAt),
            "departures": board.departures.count + board.laterDepartures.count
        ]
    }

    /// The folder of `contracts/` of `PHONE_SET_CONTRACTS`, or else of this checkout: the checkout of an old tag
    /// has no cases of the Live Activity, so its recording reads them from the checkout of today.
    nonisolated static func contractsFolder(_ part: String, from file: String = #filePath) throws -> URL {
        if let root = ProcessInfo.processInfo.environment["PHONE_SET_CONTRACTS"] {
            return URL(filePath: root, directoryHint: .isDirectory).appending(path: part, directoryHint: .isDirectory)
        }
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            let candidate = folder.appending(path: "contracts/\(part)", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            folder = folder.deletingLastPathComponent()
        }
        throw RecorderError.noContractsFolder(part)
    }

    nonisolated static func write(_ data: Data, to path: String) throws {
        guard let output else { throw RecorderError.noOutput }
        let file = output.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    nonisolated static func date(_ text: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: text) else { throw RecorderError.badDate(text) }
        return date
    }

    nonisolated static func text(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    enum RecorderError: Error {
        case noOutput
        case noContractsFolder(String)
        case badDate(String)
        case noDepartures(String)
        case noAnswer(String)
    }
}

extension PhoneSetRecorder {
    struct RecordedCase: Decodable {
        struct Answer: Decodable {
            var prim: String?
            var answeredAt: String?
            var out: String?
            var retryAt: String?
        }

        var station: String
        var now: String
        var answers: [String: Answer]
    }

    /// The server of a case: the PRIM answer of each stop with its time, or an "out" with its retry time, as the
    /// server sends them to every build (`contracts/api/`).
    final class CaseHTTPClient: HTTPClient {
        let answers: [String: RecordedCase.Answer]
        let primFolder: URL
        let now: Date

        init(answers: [String: RecordedCase.Answer], primFolder: URL, now: Date) {
            self.answers = answers
            self.primFolder = primFolder
            self.now = now
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let path = request.url?.absoluteString.removingPercentEncoding ?? ""
            guard let url = request.url, let answer = answers.first(where: { path.contains("/\($0.key)/") })?.value else {
                throw RecorderError.noAnswer(path)
            }
            let (body, status, headers) = try reply(answer, to: path)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            return (body, try #require(response))
        }

        private func reply(_ answer: RecordedCase.Answer, to path: String) throws -> (Data, Int, [String: String]) {
            if let reason = answer.out {
                let retryAt = try PhoneSetRecorder.date(answer.retryAt ?? "")
                let body = try JSONSerialization.data(withJSONObject: [
                    "status": "out", "reason": reason, "retryAt": answer.retryAt ?? ""
                ])
                let retryAfter = Int(max(0, retryAt.timeIntervalSince(now)).rounded(.up))
                return (body, 503, ["Retry-After": String(retryAfter)])
            }
            guard let prim = answer.prim, let answeredAt = answer.answeredAt else { throw RecorderError.noAnswer(path) }
            let body = try Data(contentsOf: primFolder.appending(path: "\(prim).json"))
            let lastModified = Self.httpDate(try PhoneSetRecorder.date(answeredAt))
            return (body, 200, ["Content-Type": "application/json", "Last-Modified": lastModified])
        }

        private static func httpDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            return formatter.string(from: date)
        }
    }
}
