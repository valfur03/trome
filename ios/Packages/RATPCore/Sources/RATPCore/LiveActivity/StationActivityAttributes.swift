import Foundation

public struct StationActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stationName: String
        public var trains: Trains
        public var updatedAt: Date

        public init(stationName: String, trains: Trains, updatedAt: Date) {
            self.stationName = stationName
            self.trains = trains
            self.updatedAt = updatedAt
        }
    }

    public enum Trains: Codable, Hashable, Sendable {
        case loading
        case directions(line: TransitLine, [LineDirection])
        case noData
    }

    public init() {}
}

extension StationActivityAttributes.ContentState {
    public static let loadingTimeout: TimeInterval = 60

    public init(station: Station, trains: NextTrainsState, now: Date) {
        self.init(stationName: station.name, trains: .init(trains, station: station, now: now), updatedAt: now)
    }

    public var staleDate: Date? {
        switch trains {
        case .loading:
            updatedAt.addingTimeInterval(Self.loadingTimeout)
        case .directions(_, let directions):
            directions.compactMap(\.times.first).min()
        case .noData:
            nil
        }
    }
}

extension StationActivityAttributes.Trains {
    static let maximumDirectionsWithTwoTrains = 2

    init(_ state: NextTrainsState, station: Station, now: Date) {
        switch state {
        case .idle, .loading:
            self = .loading
        case .missingKey, .noLiveData, .failed:
            self = .noData
        case .departures(let board, _):
            let upcoming = board.departures.filter { $0.time > now }
            let shownLine = station.lines.first { line in
                upcoming.contains { $0.line.mode == line.mode && $0.line.name == line.name }
            } ?? station.lines.first
            guard let shownLine else {
                self = .noData
                return
            }
            let directions = LineDirections.directions(of: shownLine, at: station, from: upcoming)
            self = directions.isEmpty
                ? .noData
                : .directions(
                    line: TransitLine(mode: shownLine.mode, name: shownLine.name),
                    Self.fittingTheLiveActivity(directions)
                )
        }
    }

    static func fittingTheLiveActivity(_ directions: [LineDirection]) -> [LineDirection] {
        guard directions.count > maximumDirectionsWithTwoTrains else { return directions }
        return directions.map { LineDirection(label: $0.label, trains: Array($0.trains.prefix(1))) }
    }
}

#if os(iOS)
import ActivityKit

extension StationActivityAttributes: ActivityAttributes {}
#endif
