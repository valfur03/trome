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
        return stations.flatMap { station in
            station.lines.flatMap { line in
                guard let scenario else { return Self.departures(of: line, at: station, from: now) }
                return Self.departures(of: line, at: station, in: scenario, from: start, now: now)
            }
        }
    }

    static func departures(of line: TransitLine, at station: Station, from start: Date) -> [Departure] {
        sides(of: line, at: station).flatMap { sideIndex, destinations in
            (0..<trainsPerSide).map { index in
                let minutes = firstTrainMinutes + sideIndex + index * minutesBetweenTrains
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
        sides(of: line, at: station).flatMap { sideIndex, destinations -> [Departure] in
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

    private static func sides(of line: TransitLine, at station: Station) -> [(Int, [String])] {
        guard let ends = line.ends else { return [] }
        let stationKey = StationCatalog.searchKey(station.name)
        return ends.sides.enumerated().compactMap { sideIndex, side in
            guard !side.contains(where: { StationCatalog.searchKey($0) == stationKey }) else { return nil }
            let destinations = ends.reachableEnds(of: side, from: station.name)
            return destinations.isEmpty ? nil : (sideIndex, destinations)
        }
    }
}
#endif
