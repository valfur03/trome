import Foundation
import Testing
@testable import TROMECore

/// An update keeps what the rider set: the code of today reads the bytes that each build in the field wrote on the
/// phone (`contracts/phone/<version>-<build>/`, recorded by `PhoneSetRecorder` from the code of that build).
/// Each store reads its value with `try?` and falls back to a default, so a renamed key, a renamed case or a new
/// required field would not crash: it would turn Automatic mode back on, or forget the Live Activity that the app
/// follows. These tests read each value through the real stores, models and rules, and check what the rider meets.
/// A value that an older build never wrote is read as it was meant: not started by the push, no pushed start, an app
/// that needs no update.
@MainActor
struct PhoneSetTests {
    nonisolated static func setNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: Fixture.contractsFolder("phone").path())
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// Each state of each set, as `<set>/<state>`.
    nonisolated static func statePaths() throws -> [String] {
        try paths(in: "states")
    }

    /// Each content of the Live Activity of each set, as `<set>/<case>.json`.
    nonisolated static func contentPaths() throws -> [String] {
        try paths(in: "live-activity")
    }

    @Test(arguments: try setNames())
    func eachSetHoldsTheStatesOfARiderAndTheLiveActivity(_ set: String) throws {
        let states = try Self.names(in: "\(set)/states")
        // The states that the recorder of the first build records; a state added later is not in the older sets.
        let required = [
            "automatic-on", "automatic-off", "automatic-snoozed", "live-activity-shown",
            "paused-after-a-swipe", "arrival-station", "last-times-no-live-data"
        ]
        #expect(Set(required).isSubset(of: states), "\(set) misses a state of a rider")
        // A case added after the recording is not in the set: a recorded set is never written again.
        #expect(try !Self.names(in: "\(set)/live-activity").isEmpty, "\(set) has no content of the Live Activity")
    }

    @Test(arguments: try statePaths())
    func theAutomaticModeThatTheRiderSetStays(_ path: String) throws {
        let phone = try RecordedPhone(path)
        let mode = { (now: Date) in
            AutomaticModeModel(
                store: AutomaticModeStore(storage: phone.storage),
                now: { now },
                sleep: { _ in throw CancellationError() }
            )
        }
        let now = Self.someDay
        switch phone.rider.automaticMode {
        case "on":
            #expect(mode(now).mode == .turnedOn)
        case "off":
            #expect(mode(now).mode == .turnedOff)
            #expect(mode(.distantFuture).allowsAutomaticStart == false, "Automatic mode off came back on")
        case "snoozed":
            let until = try #require(phone.rider.snoozedUntil.map(Fixture.date))
            #expect(mode(until.addingTimeInterval(-1)).mode == .snoozed(until: until))
            #expect(!mode(until.addingTimeInterval(-1)).allowsAutomaticStart, "the snooze ended before its time")
            #expect(mode(until).allowsAutomaticStart, "the snooze did not end at its time")
        case nil:
            #expect(phone.storage.values[AutomaticModeStore.key] == nil)
        case let other:
            Issue.record("\(path): unknown automatic mode \(other ?? "")")
        }
    }

    @Test(arguments: try statePaths())
    func theLiveActivityThatTheAppFollowsStays(_ path: String) throws {
        let phone = try RecordedPhone(path)
        let rider = phone.rider
        let state = AutoLiveActivityStore(storage: phone.storage).load()
        #expect(state.arrivalStationId == rider.arrivalStationId)
        #expect(state.shown?.stationId == rider.shown?.stationId)
        #expect(state.shown?.startedAt == rider.shown.map { Fixture.date($0.startedAt) })
        #expect(state.shown?.hasBeenNear == rider.shown?.hasBeenNear)
        #expect(state.shown?.isStartedByThePush == rider.shown.map { $0.isStartedByThePush ?? false })
        #expect(state.pause?.stationId == rider.pause?.stationId)
        #expect(state.pause?.end == rider.pause.map { Fixture.date($0.end) })
        #expect(state.pushedStart?.stationId == rider.pushedStart?.stationId)
        #expect(state.pushedStart?.answeredAt == rider.pushedStart.map { Fixture.date($0.answeredAt) })
        if state.shown != nil {
            try Self.checkTheShownLiveActivityIsFollowed(state)
        } else if state.pause != nil {
            try Self.checkThePauseHolds(state)
        } else if let stationId = rider.arrivalStationId {
            let station = try #require(StationCatalog.bundled().station(withId: stationId))
            let decision = try Self.decide(state, at: station.coordinate, now: Self.someDay)
            #expect(!decision.actions.contains(.start(station)), "the app started again at the station of its arrival")
        }
    }

    @Test(arguments: try statePaths())
    func theLastTimesOfTheLiveActivityStay(_ path: String) throws {
        let phone = try RecordedPhone(path)
        guard let expected = phone.rider.lastTimes else { return }
        let store = StationLiveActivityInputsStore(storage: phone.storage)
        let inputs = try #require(store.load(), "the last times are lost")
        #expect(inputs.station.id == expected.stationId)
        switch inputs.trains {
        case .departures(let board, let updatedAt):
            #expect(updatedAt == expected.updatedAt.map(Fixture.date))
            #expect(board.departures.count + board.laterDepartures.count == expected.departures)
        case .noLiveData:
            #expect(expected.noLiveData == true)
        default:
            Issue.record("\(path): the last times are \(inputs.trains)")
        }
    }

    /// The line page that the rider tapped to stays: the widget reads the same choice, and finds its line on the
    /// content of the same station, so the Live Activity does not go back to its first page after an update.
    @Test(arguments: try statePaths())
    func theLinePageThatTheRiderTappedToStays(_ path: String) throws {
        let phone = try RecordedPhone(path)
        let choice = LinesPageChoiceStore(storage: phone.storage).load()
        guard let expected = phone.rider.linesPageChoice else {
            #expect(choice == nil)
            return
        }
        let read = try #require(choice, "the line page that the rider tapped to is lost")
        #expect(read.activityID == expected.activityID)
        #expect(read.stationName == expected.stationName)
        #expect(read.line.mode.rawValue == expected.line["mode"])
        #expect(read.line.name == expected.line["name"])
        let set = try #require(path.split(separator: "/").first)
        let file = try Fixture.contractsFolder("phone")
            .appending(path: "\(set)/live-activity/\(expected.contentCase).json")
        let recorded = try Data(contentsOf: file)
        let content = try JSONDecoder().decode(StationActivityAttributes.ContentState.self, from: recorded)
        let index = content.chosenIndex(by: read, activityID: expected.activityID)
        #expect(index != nil, "the widget finds no page of the line that the rider tapped to")
        #expect(index != content.trains.linesPage?.firstIndex, "the line that the rider tapped to is on the first page")
    }

    /// The widget decodes the content that iOS holds, and reads back every value that the build wrote in it.
    @Test(arguments: try contentPaths())
    func theWidgetReadsTheContentOfTheLiveActivity(_ path: String) throws {
        let recorded = try Data(contentsOf: Fixture.contractsFolder("phone").appending(path: path))
        let content = try JSONDecoder().decode(StationActivityAttributes.ContentState.self, from: recorded)
        let written = try JSONSerialization.jsonObject(with: recorded)
        let read = try JSONSerialization.jsonObject(with: JSONEncoder().encode(content))
        #expect(Self.holds(read, written), "\(path): the widget reads a value of the build otherwise")
        if (written as? [String: Any])?["appNeedsUpdate"] == nil {
            #expect(content.appNeedsUpdate == false)
        }
    }
}

extension PhoneSetTests {
    static let someDay = Fixture.date("2026-10-30T08:00:00Z")

    nonisolated static func paths(in part: String) throws -> [String] {
        try setNames().flatMap { set in try names(in: "\(set)/\(part)").map { "\(set)/\(part)/\($0)" } }
    }

    nonisolated static func names(in path: String) throws -> [String] {
        let folder = try Fixture.contractsFolder("phone").appending(path: path)
        return try FileManager.default.contentsOfDirectory(atPath: folder.path())
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    static func decide(
        _ state: AutoLiveActivityState,
        at position: Coordinate?,
        now: Date
    ) throws -> AutoLiveActivityRules.Decision {
        AutoLiveActivityRules().decide(
            state: state,
            position: position,
            now: now,
            onArrival: .start,
            catalog: try StationCatalog.bundled()
        )
    }

    /// The Live Activity ends at its maximum duration from its start, and far from its station once the rider was near.
    static func checkTheShownLiveActivityIsFollowed(_ state: AutoLiveActivityState) throws {
        let shown = try #require(state.shown)
        let maximum = AutoLiveActivityRules().maximumDuration
        let before = try decide(state, at: nil, now: shown.startedAt.addingTimeInterval(maximum - 1))
        #expect(!before.actions.contains(.end), "the Live Activity ended before its time")
        let after = try decide(state, at: nil, now: shown.startedAt.addingTimeInterval(maximum))
        #expect(after.actions.contains(.end), "the Live Activity did not end at its time: its start is lost")
        let station = try #require(StationCatalog.bundled().station(withId: shown.stationId))
        let far = try farFromEveryStation(station.coordinate)
        let away = try decide(state, at: far, now: shown.startedAt.addingTimeInterval(60))
        #expect(away.actions.contains(.end) == shown.hasBeenNear, "the Live Activity did not follow its station")
    }

    /// At the paused station, the Live Activity does not come back before the end of the pause, and comes back after.
    static func checkThePauseHolds(_ state: AutoLiveActivityState) throws {
        let pause = try #require(state.pause)
        let station = try #require(StationCatalog.bundled().station(withId: pause.stationId))
        let during = try decide(state, at: station.coordinate, now: pause.end.addingTimeInterval(-60))
        #expect(!during.actions.contains(.start(station)), "the Live Activity came back during the pause")
        let after = try decide(state, at: station.coordinate, now: pause.end)
        #expect(after.actions.contains(.start(station)), "the pause did not end at its time")
    }

    /// A point about 1 km from the station, with no station within the radius of an arrival.
    static func farFromEveryStation(_ coordinate: Coordinate) throws -> Coordinate {
        let catalog = try StationCatalog.bundled()
        let offsets = [(0.01, 0.0), (-0.01, 0.0), (0.0, 0.014), (0.0, -0.014)]
        let candidates = offsets.compactMap {
            Coordinate(latitude: coordinate.latitude + $0.0, longitude: coordinate.longitude + $0.1)
        }
        let far = candidates.first {
            catalog.nearestStation(to: $0, within: AutoLiveActivityRules.arrivalRadiusMeters) == nil
        }
        return try #require(far)
    }

    /// Whether `read` holds every value of `written`: the same keys with the same values, and maybe more keys.
    nonisolated static func holds(_ read: Any, _ written: Any) -> Bool {
        switch (read, written) {
        case let (read as [String: Any], written as [String: Any]):
            written.allSatisfy { key, value in read[key].map { holds($0, value) } ?? false }
        case let (read as [Any], written as [Any]):
            read.count == written.count && zip(read, written).allSatisfy { holds($0, $1) }
        case let (read as NSObject, written as NSObject):
            read.isEqual(written)
        default:
            false
        }
    }
}

/// What the rider set, which `PhoneSetRecorder` wrote next to the bytes of the app.
struct PhoneSetRider: Decodable {
    struct Shown: Decodable {
        var stationId: String
        var startedAt: String
        var hasBeenNear: Bool
        var isStartedByThePush: Bool?
    }

    struct Pause: Decodable {
        var stationId: String
        var end: String
    }

    struct LastTimes: Decodable {
        var stationId: String
        var updatedAt: String?
        var departures: Int?
        var noLiveData: Bool?
    }

    struct PushedStart: Decodable {
        var stationId: String
        var answeredAt: String
    }

    struct PageChoice: Decodable {
        /// The case of the Live Activity whose content the rider tapped on, in `live-activity/` of the same set.
        var contentCase: String
        var activityID: String
        var stationName: String
        /// The mode and the name of the line.
        var line: [String: String]
    }

    var automaticMode: String?
    var snoozedUntil: String?
    var arrivalStationId: String?
    var shown: Shown?
    var pause: Pause?
    var lastTimes: LastTimes?
    var pushedStart: PushedStart?
    var linesPageChoice: PageChoice?
}

/// The `UserDefaults` of one state of a set, and what the rider set.
struct RecordedPhone {
    let storage = PhoneSetRecorder.RecordingStore()
    let rider: PhoneSetRider

    init(_ path: String) throws {
        let folder = try Fixture.contractsFolder("phone").appending(path: path, directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path())
        for file in files where file.hasSuffix(".json") && file != "rider.json" {
            let key = String(file.dropLast(".json".count))
            storage.values[key] = try Data(contentsOf: folder.appending(path: file))
        }
        let rider = try Data(contentsOf: folder.appending(path: "rider.json"))
        self.rider = try JSONDecoder().decode(PhoneSetRider.self, from: rider)
    }
}
