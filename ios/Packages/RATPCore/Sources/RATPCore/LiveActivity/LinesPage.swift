import Foundation

public struct LineTrains: Codable, Hashable, Sendable {
    public var line: TransitLine
    public var directions: [LineDirection]
    public var stationName: String?
    var hasADirectionWithTwoEnds: Bool?

    public init(
        line: TransitLine,
        directions: [LineDirection],
        stationName: String? = nil,
        hasADirectionWithTwoEnds: Bool = false
    ) {
        self.line = line
        self.directions = directions
        self.stationName = stationName
        self.hasADirectionWithTwoEnds = hasADirectionWithTwoEnds
    }

    var rowCount: Int {
        max(1, directions.count) + (stationName == nil ? 0 : 1)
    }

    var keepingOnlyTheNextTrains: LineTrains {
        var line = self
        line.directions = directions.map { direction in
            var direction = direction
            direction.trains = Array(direction.trains.prefix(1))
            return direction
        }
        return line
    }

    public var hasNoTrain: Bool {
        directions.allSatisfy { $0.trains.isEmpty && !$0.nextTrainIsOverAnHourAway }
    }
}

public struct SoonestTrain: Codable, Hashable, Sendable {
    public var line: TransitLine
    public var time: Date

    public init(line: TransitLine, time: Date) {
        self.line = line
        self.time = time
    }
}

public struct LinesPage: Codable, Hashable, Sendable {
    static let maximumRows = 4
    static let maximumRowsWithTwoTrains = 2

    public var lines: [LineTrains]
    public var allLines: [TransitLine]
    public var firstIndex: Int
    public var soonestTrain: SoonestTrain?
    public var nextTrainIsOverAnHourAway: Bool
    var nextTrainComesWithinTheHourAt: Date?

    public init(
        lines: [LineTrains],
        allLines: [TransitLine],
        firstIndex: Int,
        soonestTrain: SoonestTrain?,
        nextTrainIsOverAnHourAway: Bool = false
    ) {
        self.lines = lines
        self.allLines = allLines
        self.firstIndex = firstIndex
        self.soonestTrain = soonestTrain
        self.nextTrainIsOverAnHourAway = nextTrainIsOverAnHourAway
    }

    init(showing lines: [LineTrains], from index: Int, laterTrainTime: Date? = nil) {
        let firstIndex = lines.indices.contains(index) ? index : 0
        var shown: [LineTrains] = []
        var rowCount = 0
        for line in lines[firstIndex...] {
            if let first = shown.first {
                guard first.line.mode == .rer, line.line.mode == .rer,
                      rowCount + line.rowCount <= Self.maximumRows
                else { break }
            }
            shown.append(line)
            rowCount += line.rowCount
        }
        if shown.flatMap(\.directions).count > Self.maximumRowsWithTwoTrains {
            shown = shown.map(\.keepingOnlyTheNextTrains)
        }
        let soonestTrain = lines
            .flatMap { line in line.directions.compactMap(\.trains.first).map { (line: line.line, time: $0.time) } }
            .min { $0.time < $1.time }
            .map { SoonestTrain(line: $0.line, time: $0.time) }
        let nextTrainIsOverAnHourAway = soonestTrain == nil
            && lines.contains { $0.directions.contains(where: \.nextTrainIsOverAnHourAway) }
        self.init(
            lines: shown,
            allLines: lines.map(\.line),
            firstIndex: firstIndex,
            soonestTrain: soonestTrain,
            nextTrainIsOverAnHourAway: nextTrainIsOverAnHourAway
        )
        if nextTrainIsOverAnHourAway {
            nextTrainComesWithinTheHourAt = laterTrainTime?.addingTimeInterval(-DepartureBoard.farthestTimeSeconds)
        }
    }

    func nextRedrawDate(after now: Date) -> Date? {
        let trainDates = lines.flatMap { line in
            line.directions.flatMap(\.trains).flatMap { train in
                line.line.mode == .metro
                    ? PlatformStatus.changeDates(arrival: train.arrivalTime, departure: train.time)
                    : [train.time]
            }
        }
        return (trainDates + [soonestTrain?.time].compactMap { $0 }).filter { $0 > now }.min()
    }

    public var showsSeveralLines: Bool {
        allLines.count > 1
    }

    public var hasOtherLines: Bool {
        lines.count < allLines.count
    }

    public var otherLineCount: Int {
        allLines.count - lines.count
    }

    public var nextFirstIndex: Int {
        let next = firstIndex + lines.count
        return next < allLines.count ? next : 0
    }

    var keepingOnlyTheNextTrains: LinesPage {
        var page = self
        page.lines = lines.map(\.keepingOnlyTheNextTrains)
        return page
    }
}
