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
        case lines(LinesPage)
        case noData
    }

    public init() {}
}

extension StationActivityAttributes.ContentState {
    public static let loadingTimeout: TimeInterval = 60

    public init(station: Station, trains: NextTrainsState, now: Date, firstLineIndex: Int = 0) {
        self.init(
            stationName: station.name,
            trains: .init(trains, now: now, firstLineIndex: firstLineIndex),
            updatedAt: now
        )
    }

    public var staleDate: Date? {
        switch trains {
        case .loading:
            updatedAt.addingTimeInterval(Self.loadingTimeout)
        case .lines(let page):
            page.soonestTrain?.time
        case .noData:
            nil
        }
    }
}

extension StationActivityAttributes.Trains {
    public var linesPage: LinesPage? {
        guard case .lines(let page) = self else { return nil }
        return page
    }

    init(_ state: NextTrainsState, now: Date, firstLineIndex: Int) {
        switch state {
        case .idle, .loading:
            self = .loading
        case .missingKey, .noLiveData, .failed:
            self = .noData
        case .departures(let board, _):
            let upcoming = board.departures.filter { $0.time > now }
            let lines = board.lines.map { line in
                LineTrains(
                    line: TransitLine(mode: line.mode, name: line.name),
                    directions: board.station(serving: line).map { station in
                        LineDirections.directions(of: line, at: station, from: upcoming)
                    } ?? []
                )
            }
            self = lines.allSatisfy(\.directions.isEmpty)
                ? .noData
                : .lines(LinesPage(showing: lines, from: firstLineIndex))
        }
    }
}

#if os(iOS)
import ActivityKit

extension StationActivityAttributes: ActivityAttributes {}
#endif
