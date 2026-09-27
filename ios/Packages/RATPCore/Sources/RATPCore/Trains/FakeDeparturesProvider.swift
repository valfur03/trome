#if DEBUG
import Foundation

public struct FakeDeparturesProvider: DeparturesProvider {
    public static let launchArgument = "--fake-trains"
    static let firstTrainMinutes = 3
    static let minutesBetweenTrains = 4
    static let trainsPerSide = 4

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public static func ifAsked(by launchArguments: [String]) -> FakeDeparturesProvider? {
        launchArguments.contains(launchArgument) ? FakeDeparturesProvider() : nil
    }

    public func departures(at stations: [Station]) async throws -> [Departure] {
        let start = now()
        return stations.flatMap { station in
            station.lines.flatMap { line in Self.departures(of: line, at: station, from: start) }
        }
    }

    static func departures(of line: TransitLine, at station: Station, from start: Date) -> [Departure] {
        guard let ends = line.ends else { return [] }
        let stationKey = StationCatalog.searchKey(station.name)
        return ends.sides.enumerated().flatMap { sideIndex, side -> [Departure] in
            guard !side.contains(where: { StationCatalog.searchKey($0) == stationKey }) else { return [] }
            let destinations = ends.reachableEnds(of: side, from: station.name)
            guard !destinations.isEmpty else { return [] }
            return (0..<trainsPerSide).map { index in
                let minutes = firstTrainMinutes + sideIndex + index * minutesBetweenTrains
                return Departure(
                    line: line,
                    destination: destinations[index % destinations.count],
                    time: start.addingTimeInterval(TimeInterval(minutes * 60))
                )
            }
        }
    }
}
#endif
