import Foundation

public struct StationActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stationName: String
        public var trains: Trains
        public var updatedAt: Date
        public var serverIsOut: Bool
        /// The server refused the app token of this build: only an update of the app brings the times back.
        public var appNeedsUpdate: Bool
        /// Set by the app on the times that it kept after a failed call, once their stale date has passed.
        /// iOS marks a content stale no sooner than 2 minutes after the last update (seen in the log of
        /// `liveactivitiesd`), so a running app says it itself, and the widget draws the stale look at once.
        public var isMarkedStale: Bool

        public init(
            stationName: String,
            trains: Trains,
            updatedAt: Date,
            serverIsOut: Bool = false,
            appNeedsUpdate: Bool = false,
            isMarkedStale: Bool = false
        ) {
            self.stationName = stationName
            self.trains = trains
            self.updatedAt = updatedAt
            self.serverIsOut = serverIsOut
            self.appNeedsUpdate = appNeedsUpdate
            self.isMarkedStale = isMarkedStale
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: ContentStateKey.self)
            stationName = try container.decode(String.self, forKey: .stationName)
            trains = try container.decode(Trains.self, forKey: .trains)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            serverIsOut = try container.decodeIfPresent(Bool.self, forKey: .serverIsOut) ?? false
            appNeedsUpdate = try container.decodeIfPresent(Bool.self, forKey: .appNeedsUpdate) ?? false
            isMarkedStale = try container.decodeIfPresent(Bool.self, forKey: .isMarkedStale) ?? false
        }

        /// Whether the widget draws the stale look: iOS says so, or the app did.
        public func isStale(systemSaysStale: Bool) -> Bool {
            systemSaysStale || isMarkedStale
        }
    }

    public enum Trains: Codable, Hashable, Sendable {
        case loading
        case lines(LinesPage)
        case noData
    }

    public init() {}
}

private enum ContentStateKey: String, CodingKey {
    case stationName
    case trains
    case updatedAt
    case serverIsOut
    case appNeedsUpdate
    case isMarkedStale
}

extension StationActivityAttributes.ContentState {
    public static let loadingTimeout: TimeInterval = 60

    public init(
        station: Station,
        trains: NextTrainsState,
        now: Date,
        firstLineIndex: Int = 0,
        serverIsOut: Bool? = nil,
        appNeedsUpdate: Bool? = nil
    ) {
        self.init(
            stationName: station.name,
            trains: .init(trains, at: station, now: now, firstLineIndex: firstLineIndex),
            updatedAt: now,
            serverIsOut: serverIsOut ?? (trains.serverRetryAt != nil),
            appNeedsUpdate: appNeedsUpdate ?? trains.refusesTheAppToken
        )
    }

    public var staleDate: Date? {
        switch trains {
        case .loading:
            updatedAt.addingTimeInterval(Self.loadingTimeout)
        case .lines(let page):
            page.soonestTrain?.time ?? page.nextTrainComesWithinTheHourAt
        case .noData:
            nil
        }
    }

    public var keepingOnlyTheNextTrains: Self {
        guard let page = trains.linesPage else { return self }
        var state = self
        state.trains = .lines(page.keepingOnlyTheNextTrains)
        return state
    }
}

extension StationActivityAttributes.Trains {
    public var linesPage: LinesPage? {
        guard case .lines(let page) = self else { return nil }
        return page
    }

    init(_ state: NextTrainsState, at station: Station, now: Date, firstLineIndex: Int) {
        switch state {
        case .idle, .loading:
            self = .loading
        case .missingKey, .failed:
            self = .noData
        case .noLiveData:
            self = .lines(LinesPage(
                showing: station.lines.sorted(by: TransitLine.stationListOrder).map { line in
                    LineTrains(
                        line: line.shown,
                        directions: [],
                        hasADirectionWithTwoEnds: line.hasADirectionWithTwoEnds(at: station)
                    )
                },
                from: firstLineIndex
            ))
        case .departures(let board, _):
            let upcoming = board.departures.filter { $0.time > now }
            let lines = board.lines.map { line in
                let servingStation = board.station(serving: line)
                return LineTrains(
                    line: line.shown,
                    directions: servingStation.map { station in
                        let answered = LineDirections.directions(
                            of: line,
                            at: station,
                            from: upcoming,
                            later: board.laterDepartures,
                            now: now
                        )
                        guard board.hasNoAnswer(for: line) else { return answered }
                        return LineDirections.directions(
                            of: line,
                            at: station,
                            answered: answered,
                            earlier: board.earlierDepartures(of: line),
                            now: now
                        )
                    } ?? [],
                    stationName: board.otherStationName(serving: line),
                    hasADirectionWithTwoEnds: line.hasADirectionWithTwoEnds(at: servingStation ?? station)
                )
            }
            self = .lines(LinesPage(
                showing: lines,
                from: firstLineIndex,
                laterTrain: board.laterDepartures.first
            ))
        }
    }
}

private extension TransitLine {
    var shown: TransitLine {
        TransitLine(mode: mode, name: name, color: color)
    }

    func hasADirectionWithTwoEnds(at station: Station) -> Bool {
        ends?.hasADirectionWithTwoEnds(from: station.name) ?? false
    }
}

#if os(iOS)
import ActivityKit

extension StationActivityAttributes: ActivityAttributes {}
#endif
