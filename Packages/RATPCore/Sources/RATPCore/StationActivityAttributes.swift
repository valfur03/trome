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
        case departures([DepartureRow])
        case noData
    }

    public struct DepartureRow: Codable, Hashable, Sendable {
        public var line: TransitLine
        public var destination: String
        public var times: [Date]

        public init(line: TransitLine, destination: String, times: [Date]) {
            self.line = line
            self.destination = destination
            self.times = times
        }
    }

    public init() {}
}

extension StationActivityAttributes.ContentState {
    public static let loadingTimeout: TimeInterval = 60

    public init(station: Station, trains: NextTrainsState, now: Date) {
        self.init(stationName: station.name, trains: .init(trains, now: now), updatedAt: now)
    }

    public var staleDate: Date? {
        switch trains {
        case .loading:
            updatedAt.addingTimeInterval(Self.loadingTimeout)
        case .departures(let rows):
            rows.compactMap(\.times.first).min()
        case .noData:
            nil
        }
    }
}

extension StationActivityAttributes.Trains {
    init(_ state: NextTrainsState, now: Date) {
        switch state {
        case .idle, .loading:
            self = .loading
        case .missingKey, .noLiveData, .failed:
            self = .noData
        case .departures(let board, _):
            let firstRow = board.groups.lazy.compactMap { group -> StationActivityAttributes.DepartureRow? in
                let times = group.times.filter { $0 > now }
                guard !times.isEmpty else { return nil }
                return StationActivityAttributes.DepartureRow(
                    line: TransitLine(mode: group.line.mode, name: group.line.name),
                    destination: group.destination,
                    times: times
                )
            }.first
            self = firstRow.map { .departures([$0]) } ?? .noData
        }
    }
}

#if os(iOS)
import ActivityKit

extension StationActivityAttributes: ActivityAttributes {}
#endif
