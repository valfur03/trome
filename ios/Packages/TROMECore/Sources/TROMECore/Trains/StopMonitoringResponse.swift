import Foundation

struct MonitoredVisit: Equatable, Sendable {
    var monitoringRef: String?
    var lineRef: String
    var destinationRef: String?
    var destinationName: String
    var journeyRef: String?
    var time: Date
    var quayRef: String?
    var directionRef: String?
    var arrivalTime: Date?
    var isAtStop = false
    var aimedTime: Date?
    var status: String?
    var itemIdentifier: String?
    #if DEBUG
    /// Empty for a visit that no PRIM answer gave (a test), which then has no `fields` line in the log.
    var logFields = PRIMLogFields(fields: [])
    #endif

    var isCancelled: Bool {
        status == "cancelled"
    }
}

enum StopMonitoringResponse {
    static func visits(from data: Data) throws -> [MonitoredVisit] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            CamelCaseKey(pascalCase: codingPath.last?.stringValue ?? "")
        }
        let root = try decoder.decode(Root.self, from: data)
        return (root.siri.serviceDelivery.stopMonitoringDelivery ?? [])
            .flatMap { delivery in (delivery.monitoredStopVisit ?? []).compactMap(delivery.visit) }
    }
}

private struct CamelCaseKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(pascalCase: String) {
        stringValue = pascalCase.prefix(1).lowercased() + pascalCase.dropFirst()
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

private struct Root: Decodable {
    let siri: Siri
}

private struct Siri: Decodable {
    let serviceDelivery: ServiceDelivery
}

private struct ServiceDelivery: Decodable {
    let stopMonitoringDelivery: [StopMonitoringDelivery]?
}

private struct StopMonitoringDelivery: Decodable {
    let monitoredStopVisit: [MonitoredStopVisit]?
    #if DEBUG
    let responseTimestamp: PRIMRawValue?
    #endif

    func visit(_ stopVisit: MonitoredStopVisit) -> MonitoredVisit? {
        #if DEBUG
        stopVisit.monitoredVisit.map { visit in
            var visit = visit
            visit.logFields = stopVisit.logFields(answeredAt: responseTimestamp)
            return visit
        }
        #else
        stopVisit.monitoredVisit
        #endif
    }
}

private struct Value: Decodable {
    let value: String?
}

private struct FramedVehicleJourneyRef: Decodable {
    let datedVehicleJourneyRef: String?
}

private struct StopAssignment: Decodable {
    let expectedQuayRef: Value?
    let aimedQuayRef: Value?
}

private struct MonitoredCall: Decodable {
    let destinationDisplay: [Value]?
    let departureStopAssignment: StopAssignment?
    let arrivalStopAssignment: StopAssignment?
    let expectedDepartureTime: String?
    let expectedArrivalTime: String?
    let aimedDepartureTime: String?
    let aimedArrivalTime: String?
    let departureStatus: String?
    let arrivalStatus: String?
    let vehicleAtStop: Bool?
    #if DEBUG
    let departurePlatformName: PRIMRawValue?
    let arrivalPlatformName: PRIMRawValue?
    let order: PRIMRawValue?
    #endif

    var status: String? {
        departureStatus ?? arrivalStatus
    }

    var quayRef: String? {
        [departureStopAssignment, arrivalStopAssignment]
            .lazy
            .compactMap { $0?.expectedQuayRef?.value ?? $0?.aimedQuayRef?.value }
            .first { !$0.isEmpty }
    }

    var bestTime: Date? {
        [expectedDepartureTime, expectedArrivalTime, aimedDepartureTime, aimedArrivalTime]
            .lazy
            .compactMap { $0.flatMap(SIRIDate.parse) }
            .first
    }

    var arrivalTime: Date? {
        [expectedArrivalTime, aimedArrivalTime]
            .lazy
            .compactMap { $0.flatMap(SIRIDate.parse) }
            .first
    }

    var aimedTime: Date? {
        [aimedDepartureTime, aimedArrivalTime]
            .lazy
            .compactMap { $0.flatMap(SIRIDate.parse) }
            .first
    }
}

private struct MonitoredVehicleJourney: Decodable {
    let lineRef: Value?
    let destinationRef: Value?
    let destinationName: [Value]?
    let directionRef: Value?
    let framedVehicleJourneyRef: FramedVehicleJourneyRef?
    let monitoredCall: MonitoredCall?
    #if DEBUG
    let journeyNote: PRIMRawValue?
    let trainNumbers: PRIMRawValue?
    let vehicleJourneyName: PRIMRawValue?
    #endif

    var bestDestinationName: String? {
        [destinationName?.first?.value, monitoredCall?.destinationDisplay?.first?.value]
            .lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct OptionalText: Decodable {
    let text: String?

    init(from decoder: any Decoder) throws {
        text = try? decoder.singleValueContainer().decode(String.self)
    }
}

private struct MonitoredStopVisit: Decodable {
    let monitoringRef: Value?
    let itemIdentifier: OptionalText?
    let monitoredVehicleJourney: MonitoredVehicleJourney?
    #if DEBUG
    let recordedAtTime: PRIMRawValue?
    #endif

    var monitoredVisit: MonitoredVisit? {
        guard let journey = monitoredVehicleJourney,
              let lineRef = journey.lineRef?.value,
              let call = journey.monitoredCall,
              let time = call.bestTime,
              let destinationName = journey.bestDestinationName
        else {
            return nil
        }
        return MonitoredVisit(
            monitoringRef: monitoringRef?.value,
            lineRef: lineRef,
            destinationRef: journey.destinationRef?.value,
            destinationName: destinationName,
            journeyRef: journey.framedVehicleJourneyRef?.datedVehicleJourneyRef,
            time: time,
            quayRef: call.quayRef,
            directionRef: journey.directionRef?.value,
            arrivalTime: call.arrivalTime,
            isAtStop: call.vehicleAtStop ?? false,
            aimedTime: call.aimedTime,
            status: call.status,
            itemIdentifier: itemIdentifier?.text
        )
    }
}

#if DEBUG
extension MonitoredStopVisit {
    /// The fields of the debug log, each named by its place in the answer, in `MonitoredStopVisit`.
    func logFields(answeredAt responseTimestamp: PRIMRawValue?) -> PRIMLogFields {
        let journey = monitoredVehicleJourney
        let call = journey?.monitoredCall
        let departureQuay = call?.departureStopAssignment
        return PRIMLogFields(fields: [
            ("ResponseTimestamp", responseTimestamp),
            ("RecordedAtTime", recordedAtTime),
            ("DestinationName", journey?.destinationName.map(Self.raw)),
            ("DestinationDisplay", call?.destinationDisplay.map(Self.raw)),
            ("DestinationRef", journey?.destinationRef.map { Self.raw([$0]) }),
            ("JourneyNote", journey?.journeyNote),
            ("TrainNumbers", journey?.trainNumbers),
            ("VehicleJourneyName", journey?.vehicleJourneyName),
            ("DeparturePlatformName", call?.departurePlatformName),
            ("ArrivalPlatformName", call?.arrivalPlatformName),
            ("ExpectedQuayRef", departureQuay?.expectedQuayRef.map { Self.raw([$0]) }),
            ("AimedQuayRef", departureQuay?.aimedQuayRef.map { Self.raw([$0]) }),
            ("Order", call?.order),
            ("ArrivalStatus", call?.arrivalStatus.map { PRIMRawValue(text: $0.isEmpty ? "\"\"" : $0) }),
            ("DepartureStatus", call?.departureStatus.map { PRIMRawValue(text: $0.isEmpty ? "\"\"" : $0) }),
            ("ItemProducer", itemIdentifier?.text.map { PRIMRawValue(text: Self.producer(of: $0)) }),
            ("VehicleAtStop", call?.vehicleAtStop.map { PRIMRawValue(text: String($0)) })
        ])
    }

    private static func raw(_ values: [Value]) -> PRIMRawValue {
        let texts = values.map { $0.value.map { $0.isEmpty ? "\"\"" : $0 } ?? "null" }
        return PRIMRawValue(text: texts.isEmpty ? "empty" : texts.joined(separator: ","))
    }

    /// The producer of an item identifier: the part before its first colon (`RATP-SIV`, `SNCF_MAGENTA_PRD`).
    static func producer(of itemIdentifier: String) -> String {
        guard let colon = itemIdentifier.firstIndex(of: ":") else { return "none" }
        return String(itemIdentifier[..<colon])
    }
}
#endif

enum SIRIDate {
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractionalSeconds = Date.ISO8601FormatStyle()

    static func parse(_ text: String) -> Date? {
        (try? withFractionalSeconds.parse(text)) ?? (try? withoutFractionalSeconds.parse(text))
    }
}
