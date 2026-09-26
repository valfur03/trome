import Foundation

struct MonitoredVisit: Equatable, Sendable {
    var monitoringRef: String?
    var lineRef: String
    var destinationRef: String?
    var destinationName: String
    var journeyRef: String?
    var time: Date
    var quayRef: String?
}

enum StopMonitoringResponse {
    static func visits(from data: Data) throws -> [MonitoredVisit] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            CamelCaseKey(pascalCase: codingPath.last?.stringValue ?? "")
        }
        let root = try decoder.decode(Root.self, from: data)
        return (root.siri.serviceDelivery.stopMonitoringDelivery ?? [])
            .flatMap { $0.monitoredStopVisit ?? [] }
            .compactMap(\.monitoredVisit)
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
}

private struct Value: Decodable {
    let value: String?
}

private struct FramedVehicleJourneyRef: Decodable {
    let datedVehicleJourneyRef: String?
}

private struct MonitoredCall: Decodable {
    let destinationDisplay: [Value]?
    let expectedDepartureTime: String?
    let expectedArrivalTime: String?
    let aimedDepartureTime: String?
    let aimedArrivalTime: String?
    let departureStatus: String?
    let arrivalStatus: String?

    var isCancelled: Bool {
        (departureStatus ?? arrivalStatus) == "cancelled"
    }

    var bestTime: Date? {
        [expectedDepartureTime, expectedArrivalTime, aimedDepartureTime, aimedArrivalTime]
            .lazy
            .compactMap { $0.flatMap(SIRIDate.parse) }
            .first
    }
}

private struct MonitoredVehicleJourney: Decodable {
    let lineRef: Value?
    let destinationRef: Value?
    let destinationName: [Value]?
    let framedVehicleJourneyRef: FramedVehicleJourneyRef?
    let monitoredCall: MonitoredCall?

    var bestDestinationName: String? {
        [destinationName?.first?.value, monitoredCall?.destinationDisplay?.first?.value]
            .lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct MonitoredStopVisit: Decodable {
    let monitoringRef: Value?
    let monitoredVehicleJourney: MonitoredVehicleJourney?

    var monitoredVisit: MonitoredVisit? {
        guard let journey = monitoredVehicleJourney,
              let lineRef = journey.lineRef?.value,
              let call = journey.monitoredCall,
              !call.isCancelled,
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
            time: time
        )
    }
}

enum SIRIDate {
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractionalSeconds = Date.ISO8601FormatStyle()

    static func parse(_ text: String) -> Date? {
        (try? withFractionalSeconds.parse(text)) ?? (try? withoutFractionalSeconds.parse(text))
    }
}
