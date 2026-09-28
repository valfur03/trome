import Foundation

public enum PlatformStatus: String, Codable, Hashable, Sendable {
    case approaching
    case atPlatform

    static let approachingSeconds: TimeInterval = 60

    init?(of departure: Departure, at now: Date) {
        let arrival = departure.arrivalTime ?? departure.time
        if departure.isAtStop || (arrival <= now && now < departure.time) {
            self = .atPlatform
        } else if arrival.timeIntervalSince(now) < Self.approachingSeconds {
            self = .approaching
        } else {
            return nil
        }
    }

    static func changeDates(arrival: Date?, departure: Date) -> [Date] {
        let arrival = arrival ?? departure
        return [arrival.addingTimeInterval(1 - approachingSeconds), arrival, departure]
    }
}
