#if DEBUG
import Foundation

public struct FakeDeparturesProvider: DeparturesProvider {
    static let launchArgument = "--fake-trains"
    static let firstTrainMinutes = 3
    static let minutesBetweenTrains = 4
    static let trainsPerSide = 4

    let scenario: FakeTrainsScenario?
    let start: Date
    private let now: @Sendable () -> Date

    init(
        scenario: FakeTrainsScenario? = nil,
        start: Date = Date(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scenario = scenario
        self.start = start
        self.now = now
    }

    public static func ifAsked(by launchArguments: [String]) -> FakeDeparturesProvider? {
        launchArguments.contains(launchArgument) ? FakeDeparturesProvider() : nil
    }

    public func departures(at stations: [Station]) async throws -> [Departure] {
        let now = now()
        if let retryAt = scenario?.serverRetryAt(from: start, now: now) {
            throw NextTrainsError.serverOut(retryAt: retryAt)
        }
        if scenario?.refusesTheAppToken(from: start, now: now) == true {
            throw NextTrainsError.appTokenRefused
        }
        return stations.flatMap { station in
            station.lines.flatMap { line in
                guard let scenario else { return Self.departures(of: line, at: station, from: start, now: now) }
                return Self.departures(of: line, at: station, in: scenario, from: start, now: now)
            }
        }
    }

    /// The default fake trains. Train `k` of the side `s` leaves `firstTrainMinutes + s + k * minutesBetweenTrains`
    /// minutes after `start`, the launch: each fetch gives the next trains of that same timetable, so a train that the
    /// app counts down leaves at its time, and the next one takes its place.
    static func departures(of line: TransitLine, at station: Station, from start: Date, now: Date) -> [Departure] {
        let minutesSinceStart = now.timeIntervalSince(start) / 60
        return line.departureSides(at: station).flatMap { sideIndex, destinations in
            let firstMinutes = firstTrainMinutes + sideIndex
            let left = (minutesSinceStart - Double(firstMinutes)) / Double(minutesBetweenTrains)
            let next = max(0, Int(left.rounded(.down)) + 1)
            return (next..<next + trainsPerSide).map { index in
                let minutes = firstMinutes + index * minutesBetweenTrains
                return Departure(
                    line: line,
                    destination: destinations[index % destinations.count],
                    time: start.addingTimeInterval(TimeInterval(minutes * 60))
                )
            }
        }
    }

    static func departures(
        of line: TransitLine,
        at station: Station,
        in scenario: FakeTrainsScenario,
        from start: Date,
        now: Date
    ) -> [Departure] {
        line.departureSides(at: station).flatMap { sideIndex, destinations -> [Departure] in
            let shift = Double(sideIndex)
            let minutesSinceStart = now.timeIntervalSince(start) / 60
            let trains = scenario.trains(leavingAfter: minutesSinceStart - shift, count: trainsPerSide).map { train in
                let time = start.addingTimeInterval((train.departureMinutes + shift) * 60)
                return Departure(
                    line: line,
                    destination: destinations[scenario.endIndex(of: train, amongEnds: destinations.count)],
                    time: time,
                    arrivalTime: train.waitsAtThePlatformFromTheStart
                        ? start
                        : time.addingTimeInterval(-FakeTrainsScenario.stopSeconds)
                )
            }
            guard let laterEnd = scenario.laterTrainEndIndex(amongEnds: destinations.count) else { return trains }
            let laterTime = start.addingTimeInterval((FakeTrainsScenario.laterTrainMinutes + shift) * 60)
            return trains + [Departure(
                line: line,
                destination: destinations[laterEnd],
                time: laterTime,
                arrivalTime: laterTime.addingTimeInterval(-FakeTrainsScenario.stopSeconds)
            )]
        }
    }
}
#endif
