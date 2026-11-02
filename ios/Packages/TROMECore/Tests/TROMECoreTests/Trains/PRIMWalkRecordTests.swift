import Foundation
import Testing
@testable import TROMECore

/// The walk record keeps the PRIM fields of the two rare cases that a walk must explain with no second ask: two
/// entries of one side under 60 s apart (the ghost row), and a train at the platform that the Live Activity hides
/// because its time has passed. Nothing else from PRIM goes in the record.
@MainActor
struct PRIMWalkRecordTests {
    private static let stopArea = "STIF:StopArea:SP:470549:"
    private static let platform = "STIF:StopPoint:Q:473921:"
    /// The time of the real public La Défense RER A answer (2026-04-27): its pair and its standing train are the
    /// ones that the notes of the spike recorded, with the values that they give; the other fields have the shape
    /// of that answer, not its values (no copy of the answer is kept).
    private static let answerTime = "2026-04-27T12:33:29.300Z"
    private let storage = InMemoryKeyValueStore()

    private struct Entry {
        var destination: String
        var expected: String
        var aimed: String
        var mission: String
        var number: String
        var atStop = false
        var arrival: String?
        var arrivalStatus = "onTime"
        var recorded = "2026-04-27T12:32:00.000Z"
    }

    private static let standingSaintGermain = Entry(
        destination: "Saint-Germain-en-Laye", expected: "2026-04-27T12:32:59.000Z",
        aimed: "2026-04-27T12:32:00.000Z", mission: "ZEUS", number: "ZEUS41", atStop: true,
        arrival: "2026-04-27T12:32:39.000Z", arrivalStatus: "arrived", recorded: "2026-04-27T12:33:05.000Z"
    )
    private static let rueil = Entry(
        destination: "Rueil-Malmaison", expected: "2026-04-27T12:39:26.000Z", aimed: "2026-04-27T12:39:00.000Z",
        mission: "YRZZ", number: "YRZZ01"
    )
    private static let cergy = Entry(
        destination: "Cergy-Le-Haut", expected: "2026-04-27T12:40:13.000Z", aimed: "2026-04-27T12:38:00.000Z",
        mission: "UZAR", number: "UZAR93"
    )
    private static let poissy = Entry(
        destination: "Poissy", expected: "2026-04-27T12:46:10.000Z", aimed: "2026-04-27T12:46:00.000Z",
        mission: "TOCA", number: "TOCA17"
    )
    private static let laDefense = [standingSaintGermain, rueil, cergy, poissy]

    private static func answer(_ entries: [Entry], extra: String = "") -> Data {
        let visits = entries.enumerated().map { rank, entry in
            """
            {"RecordedAtTime": "\(entry.recorded)",
             "ItemIdentifier": "SNCF_MAGENTA_PRD:Item::\(entry.number):LOC",
             "MonitoringRef": {"value": "\(stopArea)"},
             "MonitoredVehicleJourney": {
               "LineRef": {"value": "STIF:Line::C01742:"},
               "FramedVehicleJourneyRef": {
                 "DatedVehicleJourneyRef": "SNCF_MAGENTA_PRD:VehicleJourney::\(entry.number)"
               },
               "DirectionRef": {"value": "Aller"},
               "DestinationRef": {"value": "STIF:StopArea:SP:90000\(rank):"},
               "DestinationName": [{"value": "\(entry.destination)"}],
               "JourneyNote": [{"value": "\(entry.mission)"}],
               "VehicleJourneyName": [{"value": "\(entry.number)"}],
               \(extra)
               "MonitoredCall": {
                 "VehicleAtStop": \(entry.atStop),
                 "DestinationDisplay": [{"value": "\(entry.destination)"}],
                 \(entry.arrival.map { "\"ExpectedArrivalTime\": \"\($0)\"," } ?? "")
                 "ExpectedDepartureTime": "\(entry.expected)",
                 "AimedDepartureTime": "\(entry.aimed)",
                 "DepartureStopAssignment": {"ExpectedQuayRef": {"value": "\(platform)"}},
                 "DeparturePlatformName": {"value": "2"},
                 "ArrivalStatus": "\(entry.arrivalStatus)",
                 "DepartureStatus": "onTime"
               }
             }}
            """
        }
        return Data("""
            {"Siri": {"ServiceDelivery": {"StopMonitoringDelivery": [{
              "ResponseTimestamp": "\(answerTime)",
              "MonitoredStopVisit": [\(visits.joined(separator: ","))]
            }]}}}
            """.utf8)
    }

    private func station(_ name: String) throws -> Station {
        try #require(try StationCatalog.bundled().stations.first { $0.name == name })
    }

    /// The record after one refresh of a station by the app, through the server as a Release build asks.
    private func record(
        _ data: Data,
        at name: String = "La Défense",
        now: Date = Fixture.date(answerTime),
        in log: WakeLog? = nil,
        source: TrainDataSource = .server(.test)
    ) async throws -> (WakeLog, StubHTTPClient) {
        let log = log ?? WakeLog(storage: storage, now: { now })
        let client = StubHTTPClient(headerFields: ["Last-Modified": "Mon, 27 Apr 2026 12:33:29 GMT"]) { _ in
            (data, 200)
        }
        let provider = PRIMDeparturesProvider(source: source, httpClient: client, walkRecord: log, now: { now })
        _ = try await provider.departuresAnswer(at: [try station(name)])
        return (log, client)
    }

    private func groups(_ log: WakeLog) -> [String] {
        log.entries.filter { $0.kind == .prim }.map(\.text)
    }

    private func groups(_ log: WakeLog, of case: PRIMWalkRecord.Case) -> [String] {
        groups(log).filter { $0.hasPrefix(`case`.title + ": ") }
    }

    @Test func writesThePairAndTheStandingTrainOfTheRealLaDefenseAnswerWithTheirFields() async throws {
        let (log, _) = try await record(Self.answer(Self.laDefense))

        let groups = groups(log)
        #expect(groups.count == 2)
        let pair = try #require(groups.first { $0.hasPrefix("PRIM, two entries under 60 s apart: La Défense\n") })
        let pairEntries = pair.split(separator: "\n").dropFirst().filter { !$0.contains(" | fields | ") }
        #expect(pairEntries.count == 2)
        #expect(pairEntries[0].contains("journey SNCF_MAGENTA_PRD:VehicleJourney::YRZZ01"))
        #expect(pairEntries[0].hasSuffix(" | shows 6 min"))
        #expect(pairEntries[1].contains("journey SNCF_MAGENTA_PRD:VehicleJourney::UZAR93"))
        #expect(pairEntries[1].hasSuffix(" | shows 7 min"))
        #expect(pair.contains("| fields | ResponseTimestamp \(Self.answerTime) | RecordedAtTime 2026-04-27T12:32:00"))
        #expect(pair.contains("| JourneyNote YRZZ |") && pair.contains("| VehicleJourneyName UZAR93 |"))

        let standing = try #require(groups.first { $0.hasPrefix("PRIM, at the platform past its time: La Défense\n") })
        #expect(standing.contains("journey SNCF_MAGENTA_PRD:VehicleJourney::ZEUS41"))
        #expect(standing.contains(" | 30 s past its time"))
        #expect(standing.contains("| ResponseTimestamp \(Self.answerTime) | RecordedAtTime 2026-04-27T12:33:05.000Z"))
        #expect(standing.contains("| ArrivalStatus arrived |") && standing.contains("| VehicleAtStop true"))

        #expect(!groups.joined().contains("TOCA17"), "an entry of neither case is in the record")
    }

    /// The bounds of each case: 60 s apart is not a pair (59 s is), and a train at the platform before its time,
    /// or past it but not at the platform, is not a standing train.
    @Test(arguments: [
        ("2026-04-27T12:40:26.000Z", false, 0),
        ("2026-04-27T12:40:25.000Z", false, 1),
        ("2026-04-27T12:40:26.000Z", true, 1)
    ])
    func writesACaseOnlyWithinItsBounds(cergyTime: String, standsAtThePlatform: Bool, groupCount: Int) async throws {
        var cergy = Self.cergy
        cergy.expected = cergyTime
        var saintGermain = Self.standingSaintGermain
        saintGermain.atStop = standsAtThePlatform
        let earlyAtThePlatform = Entry(
            destination: "Poissy", expected: "2026-04-27T12:34:30.000Z", aimed: "2026-04-27T12:34:00.000Z",
            mission: "TOCA", number: "TOCA17", atStop: true
        )

        let (log, _) = try await record(Self.answer([saintGermain, earlyAtThePlatform, Self.rueil, cergy]))

        #expect(groups(log).count == groupCount, "\(groups(log))")
    }

    /// A real answer with neither case, and the hand-made La Défense answer, whose train at the platform has
    /// not reached its time.
    @Test(arguments: [
        ("stop-monitoring-liege-171032", "Liège", "2026-10-02T15:10:32Z"),
        ("stop-monitoring-la-defense-rer-a-at-stop", "La Défense", "2026-10-01T10:31:50.412Z")
    ])
    func writesNothingForANormalAnswer(answer: String, station: String, time: String) async throws {
        let (log, _) = try await record(Fixture.data(answer), at: station, now: Fixture.date(time))

        #expect(log.entries.isEmpty, "\(log.entries.map(\.text))")
    }

    /// Two real metro answers of Liège hold an entry that PRIM says is at the platform 23 min past its time:
    /// the record keeps it, as the length of such an entry is what the bound of a train shown at the platform needs.
    @Test(arguments: [
        ("stop-monitoring-liege-170043", "2026-10-02T15:00:43Z", "1409 s past its time"),
        ("stop-monitoring-liege-170558", "2026-10-02T15:05:58Z", "s past its time")
    ])
    func writesTheTrainThatARealMetroAnswerSaysIsStillAtThePlatform(answer: String, time: String, late: String)
        async throws {
        let (log, _) = try await record(Fixture.data(answer), at: "Liège", now: Fixture.date(time))

        let groups = groups(log)
        #expect(groups.count == 1)
        #expect(groups.first?.hasPrefix("PRIM, at the platform past its time: Liège\n") == true)
        #expect(groups.first?.contains(late) == true)
    }

    private func clock(at time: String) -> TestClock {
        let clock = TestClock()
        clock.advance(by: Fixture.date(time).timeIntervalSince(clock.now))
        return clock
    }

    @Test func writesEachCaseOncePerStationAndHour() async throws {
        let clock = clock(at: Self.answerTime)
        let log = WakeLog(storage: storage, now: { clock.now })
        let data = Self.answer(Self.laDefense)

        for seconds in [0, 30, 59 * 60 + 29] {
            clock.advance(by: TimeInterval(seconds))
            _ = try await record(data, now: clock.now, in: log)
        }
        #expect(groups(log).count == 2)

        clock.advance(by: 2)
        _ = try await record(data, now: clock.now, in: log)
        #expect(groups(log).count == 4)
    }

    /// Each case keeps its own newest groups, and no line of another kind goes.
    @Test func keepsTheNewestGroupsOfEachCaseApartAndNoOtherLineGoes() {
        let clock = clock(at: Self.answerTime)
        let log = WakeLog(storage: storage, now: { clock.now })
        log.record(.decision, "Arrived at Joinville-le-Pont")
        for index in 0...max(WakeLog.maximumPRIMGroups(of: .pair), WakeLog.maximumPRIMGroups(of: .standing)) {
            for `case` in PRIMWalkRecord.Case.allCases {
                log.record([PRIMWalkRecord.Group(`case`, at: "station \(index)", lines: ["entry"])])
            }
            clock.advance(by: 1)
        }

        for `case` in PRIMWalkRecord.Case.allCases {
            let bound = WakeLog.maximumPRIMGroups(of: `case`)
            let kept = groups(log, of: `case`)
            #expect(kept.count == bound)
            #expect(kept.first?.hasPrefix("\(`case`.title): station \(bound)\n") == true)
            #expect(kept.last?.hasPrefix("\(`case`.title): station 1\n") == true)
        }
        #expect(log.entries.last?.text == "Arrived at Joinville-le-Pont")
    }

    private static let liegeStandingAnswers = [
        ("stop-monitoring-liege-170043", "2026-10-02T15:00:43Z"),
        ("stop-monitoring-liege-170558", "2026-10-02T15:05:58Z")
    ]

    /// The ghost pair is the only trace of the ghost row, and a walk meets it once. The walk goes on for hours, and
    /// real metro answers keep a train at the platform 23 min past its time, so it writes a standing train about
    /// once per station and hour: more of them than their bound never push the pair out.
    @Test func moreStandingTrainsThanTheirBoundNeverPushOutThePairOfTheRealLaDefenseAnswer() async throws {
        let clock = clock(at: Self.answerTime)
        let log = WakeLog(storage: storage, now: { clock.now })
        _ = try await record(Self.answer(Self.laDefense), in: log)
        for index in 0..<WakeLog.maximumPRIMGroups(of: .standing) {
            clock.advance(by: 1)
            log.record([PRIMWalkRecord.Group(.standing, at: "station \(index)", lines: ["entry"])])
        }
        for (answer, time) in Self.liegeStandingAnswers {
            clock.advance(by: WakeLog.primGroupSpacing + 1)
            _ = try await record(Fixture.data(answer), at: "Liège", now: Fixture.date(time), in: log)
        }

        let standing = groups(log, of: .standing)
        #expect(standing.count == WakeLog.maximumPRIMGroups(of: .standing))
        #expect(standing.prefix(2).allSatisfy { $0.hasPrefix("PRIM, at the platform past its time: Liège\n") })
        let pair = try #require(groups(log, of: .pair).first)
        #expect(groups(log, of: .pair).count == 1)
        #expect(pair.hasPrefix("PRIM, two entries under 60 s apart: La Défense\n"))
        #expect(pair.contains("VehicleJourney::YRZZ01") && pair.contains("VehicleJourney::UZAR93"))
    }

    /// The reverse: more pairs than their bound never push out the train that a real metro answer says is still
    /// at the platform.
    @Test func morePairsThanTheirBoundNeverPushOutTheStandingTrainOfTheRealLiegeAnswer() async throws {
        let clock = clock(at: Self.answerTime)
        let log = WakeLog(storage: storage, now: { clock.now })
        let (answer, time) = Self.liegeStandingAnswers[0]
        _ = try await record(Fixture.data(answer), at: "Liège", now: Fixture.date(time), in: log)
        clock.advance(by: 1)
        _ = try await record(Self.answer(Self.laDefense), in: log)
        for index in 0..<WakeLog.maximumPRIMGroups(of: .pair) {
            clock.advance(by: 1)
            log.record([PRIMWalkRecord.Group(.pair, at: "station \(index)", lines: ["entry"])])
        }

        let pairs = groups(log, of: .pair)
        #expect(pairs.count == WakeLog.maximumPRIMGroups(of: .pair))
        #expect(!pairs.contains { $0.contains("La Défense") }, "the bound of the pairs holds")
        let standing = groups(log, of: .standing)
        #expect(standing.count == 2)
        #expect(standing.last?.hasPrefix("PRIM, at the platform past its time: Liège\n") == true)
        #expect(standing.last?.contains("1409 s past its time") == true)
    }

    /// The record never leaves the phone and holds no position: the groups hold no coordinate, even when PRIM
    /// sends the position of the train, no key, no token, and the app makes no call for them.
    @Test(arguments: [false, true])
    func theSharedRecordOfTheseGroupsHoldsNoPositionNoKeyAndNoToken(throughTheServer: Bool) async throws {
        let key = "prim-key-7f3a9c41"
        let trainPosition = #""VehicleLocation": {"Longitude": 2.2377231, "Latitude": 48.8921984},"#
        let (log, client) = try await record(
            Self.answer(Self.laDefense, extra: trainPosition),
            source: throughTheServer ? .server(.test) : .prim(apiKey: key)
        )

        let report = log.report(phone: ["Location: Always, precise"])
        let laDefense = try station("La Défense")
        #expect(groups(log).count == 2)
        #expect(client.requests.count == PRIMDeparturesProvider.stopRequests(for: [laDefense]).count)
        #expect(report.firstMatch(of: /\d+[.,]\d{4,}/) == nil, "a coordinate in the shared record: \(report)")
        for degrees in [laDefense.latitude, laDefense.longitude, 48.8921984, 2.2377231] {
            #expect(!report.contains(String(format: "%.2f", degrees)))
        }
        for secret in [key, "test-app-token", "apikey", "Authorization", "Bearer", "Last-Modified"] {
            #expect(!report.localizedCaseInsensitiveContains(secret), "the record holds \(secret)")
        }
    }
}
