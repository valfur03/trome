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

extension PlatformStatus {
    /// The statuses of the trains of one metro direction, in the order they leave.
    /// One metro platform holds one train of a direction, and trains do not overtake there:
    /// so after a train that has not reached the platform yet, the later trains of that platform read their minutes,
    /// whatever PRIM says of them. A train that has left (kept a few seconds) no longer holds the platform.
    static func ofEach(_ trains: [Departure], at now: Date, oneTrainPerPlatform: Bool) -> [PlatformStatus?] {
        var platformsWithATrainOnTheWay: Set<String?> = []
        return trains.map { train in
            let own = PlatformStatus(of: train, at: now)
            guard oneTrainPerPlatform else { return own }
            let status = platformsWithATrainOnTheWay.contains(train.quayRef) ? nil : own
            if status != .atPlatform, train.time > now {
                platformsWithATrainOnTheWay.insert(train.quayRef)
            }
            return status
        }
    }
}
