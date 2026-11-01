import Foundation
import Synchronization
import Testing
@testable import TROMECore

/// The debug log keeps every field of a PRIM entry that names a train, so that a recording can tell two entries of
/// one minute apart: a plan entry that was never updated, or a real second train.
struct PRIMAnswerLogFieldsTests {
    private static let northQuay = "STIF:StopPoint:Q:22225:"
    private static let fieldNames = [
        "ResponseTimestamp", "RecordedAtTime", "DestinationName", "DestinationDisplay", "DestinationRef",
        "JourneyNote", "TrainNumbers", "VehicleJourneyName", "DeparturePlatformName", "ArrivalPlatformName",
        "ExpectedQuayRef", "AimedQuayRef", "Order", "ArrivalStatus", "DepartureStatus", "ItemProducer",
        "VehicleAtStop"
    ]
    private static let liegeAnswers = [
        "stop-monitoring-liege-170043", "stop-monitoring-liege-170558", "stop-monitoring-liege-171032"
    ]

    private func liege() throws -> Station {
        try #require(try StationCatalog.bundled().stations.first { $0.name == "Liège" })
    }

    private func lines(of data: Data) throws -> [String] {
        let answer = PRIMDeparturesProvider.Answer(
            stopRequest: PRIMDeparturesProvider.StopRequest(monitoringRef: Self.northQuay, lineCodes: ["C01383"]),
            visits: .success(try StopMonitoringResponse.visits(from: data)),
            askedAt: Fixture.date("2026-10-02T15:00:42.500Z")
        )
        return PRIMAnswerLog.lines(
            of: [answer], at: [try liege()], now: Fixture.date("2026-10-02T15:00:43Z"), timeZone: .gmt
        )
    }

    private func fieldLines(_ lines: [String]) -> [String] {
        lines.filter { $0.contains(" | fields | ") }
    }

    @Test func writesEachFieldOfAnEntryOfARealAnswerAndSaysWhichAreAbsent() throws {
        let lines = try lines(of: Fixture.data("stop-monitoring-liege-170043"))

        let expected: String = "PRIM \(Self.northQuay) | call 2026-10-02T15:00:42.500Z | entry 1 | fields"
            + " | ResponseTimestamp 2026-10-02T15:00:43.197Z | RecordedAtTime 2026-10-02T15:00:43.000Z"
            + " | DestinationName Asnières-Gennevilliers Les Courtilles"
            + " | DestinationDisplay Asnières-Gennevilliers Les Courtilles | DestinationRef STIF:StopPoint:Q:22233:"
            + " | JourneyNote absent | TrainNumbers absent | VehicleJourneyName absent | DeparturePlatformName absent"
            + " | ArrivalPlatformName absent | ExpectedQuayRef absent | AimedQuayRef absent | Order absent"
            + " | ArrivalStatus absent | DepartureStatus onTime | ItemProducer RATP-SIV | VehicleAtStop true"
        #expect(fieldLines(lines).first == expected)
    }

    @Test(arguments: liegeAnswers)
    func writesTheFieldsOfEveryEntryRightAfterItsLineInTheOrderOfTheAnswer(answer: String) throws {
        let data = try Fixture.data(answer)
        let entryCount = try StopMonitoringResponse.visits(from: data).count
        let lines = try lines(of: data)

        #expect(entryCount > 0)
        #expect(lines.count == 1 + 2 * entryCount)
        for rank in 1...entryCount {
            let fields = lines[2 * rank]
            #expect(lines[2 * rank - 1].contains(" | entry \(rank) | "))
            #expect(fields.contains(" | entry \(rank) | fields | "))
            let names = fields.components(separatedBy: " | fields | ").last?.components(separatedBy: " | ")
                .map { field in String(field.prefix { $0 != " " }) }
            #expect(names == Self.fieldNames)
        }
    }

    @Test func writesTheTrainFieldsOfAnRERAnswerAndNeverAnEmptyTextThatReadsLikeAValue() throws {
        let answer = """
        {"Siri": {"ServiceDelivery": {"StopMonitoringDelivery": [{
          "ResponseTimestamp": "2026-11-02T07:31:20.114Z",
          "MonitoredStopVisit": [{
            "RecordedAtTime": "2026-11-02T01:18:00.000Z",
            "ItemIdentifier": "SNCF_MAGENTA_PRD:Item::470549-1:",
            "MonitoringRef": {"value": "STIF:StopPoint:Q:22225:"},
            "MonitoredVehicleJourney": {
              "LineRef": {"value": "STIF:Line::C01383:"},
              "DestinationRef": {"value": ""},
              "DestinationName": [],
              "JourneyNote": [{"value": "ZEUS"}],
              "TrainNumbers": {"TrainNumberRef": [{"value": "154321"}, {"value": "154322"}]},
              "VehicleJourneyName": [{"value": "ZEUS54"}],
              "MonitoredCall": {
                "Order": 23,
                "VehicleAtStop": false,
                "DestinationDisplay": [{"value": "La Défense"}],
                "ExpectedDepartureTime": "2026-11-02T07:32:00.000Z",
                "DepartureStopAssignment": {
                  "ExpectedQuayRef": {"value": "STIF:StopPoint:Q:90011:"},
                  "AimedQuayRef": {"value": "STIF:StopPoint:Q:90012:"}
                },
                "DeparturePlatformName": {"value": "2"},
                "ArrivalPlatformName": {"value": ""},
                "ArrivalStatus": "arrived",
                "DepartureStatus": ""
              }
            }
          }]
        }]}}}
        """

        let fields = try #require(fieldLines(lines(of: Data(answer.utf8))).first)

        let expected: String = " | fields | ResponseTimestamp 2026-11-02T07:31:20.114Z"
            + " | RecordedAtTime 2026-11-02T01:18:00.000Z | DestinationName empty | DestinationDisplay La Défense"
            + " | DestinationRef \"\" | JourneyNote ZEUS | TrainNumbers 154321,154322 | VehicleJourneyName ZEUS54"
            + " | DeparturePlatformName 2 | ArrivalPlatformName \"\" | ExpectedQuayRef STIF:StopPoint:Q:90011:"
            + " | AimedQuayRef STIF:StopPoint:Q:90012: | Order 23 | ArrivalStatus arrived | DepartureStatus \"\""
            + " | ItemProducer SNCF_MAGENTA_PRD | VehicleAtStop false"
        #expect(fields.hasSuffix(expected), "\(fields)")
    }

    /// The log of the phone cuts a line after 1024 bytes, and the end of the line holds the fields.
    @Test(arguments: liegeAnswers)
    func writesEachLineShortEnoughForTheLogOfThePhoneToKeepItWhole(answer: String) throws {
        let lines = try lines(of: Fixture.data(answer))

        #expect(lines.allSatisfy { $0.utf8.count < 1024 })
    }

    @Test(arguments: [false, true])
    func writesNoKeyNoTokenAndNoHeaderOfTheCall(throughTheServer: Bool) async throws {
        let key = "prim-key-7f3a9c41"
        let headers = ["apikey": key, "Authorization": "Bearer test-app-token", "Last-Modified": Self.lastModified]
        let client = StubHTTPClient(headerFields: headers) { request in
            #expect(request.value(forHTTPHeaderField: throughTheServer ? "Authorization" : "apikey") != nil)
            return (try Fixture.data("stop-monitoring-liege-170043"), 200)
        }
        let lines = Mutex<[String]>([])
        let log: @Sendable (String) -> Void = { line in lines.withLock { $0.append(line) } }
        let provider = throughTheServer
            ? PRIMDeparturesProvider(source: .server(.test), httpClient: client, log: log)
            : PRIMDeparturesProvider(apiKey: key, httpClient: client, log: log)

        _ = try await provider.departures(at: [try liege()])

        let logged = lines.withLock { $0 }
        #expect(fieldLines(logged).count >= 8)
        let secrets = [key, "test-app-token", "apikey", "Authorization", "Bearer", "Accept", "application/json",
                       "Last-Modified"]
        for secret in secrets {
            #expect(!logged.contains { $0.localizedCaseInsensitiveContains(secret) }, "a line holds \(secret)")
        }
    }

    private static let lastModified = "Fri, 02 Oct 2026 15:00:43 GMT"
}
