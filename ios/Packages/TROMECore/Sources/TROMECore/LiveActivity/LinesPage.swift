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

    var keepingOnlyTheNextTrains: LineTrains {
        var line = self
        line.directions = directions.map { direction in
            var direction = direction
            direction.trains = Array(direction.trains.prefix(1))
            direction.trainsOfEachEnd = direction.trainsOfEachEnd?.map { endTrains in
                var endTrains = endTrains
                endTrains.trains = Array(endTrains.trains.prefix(1))
                return endTrains
            }
            return direction
        }
        return line
    }

    public var hasNoTrain: Bool {
        directions.allSatisfy { $0.trains.isEmpty && !$0.nextTrainIsOverAnHourAway && !$0.hasNoAnswer }
    }
}

public struct SoonestTrain: Codable, Hashable, Sendable {
    public var line: TransitLine
    public var time: Date
    var train: LineDirection.Train?

    public init(line: TransitLine, time: Date) {
        self.line = line
        self.time = time
    }

    init(line: TransitLine, train: LineDirection.Train) {
        self.init(line: line, time: train.time)
        self.train = train
    }

    var redrawDates: [Date] {
        guard let train else { return [time] }
        return PlatformStatus.changeDates(arrival: train.arrivalTime, departure: train.time)
    }
}

public struct LinesPage: Codable, Hashable, Sendable {
    static let maximumRowsWithTwoTrains = 2

    public var lines: [LineTrains]
    public var allLines: [TransitLine]
    public var firstIndex: Int
    public var soonestTrain: SoonestTrain?
    public var nextTrainIsOverAnHourAway: Bool
    var nextTrainComesWithinTheHourAt: Date?
    var lineOfTheTrainOverAnHourAway: TransitLine?
    var lineWithNoAnswer: TransitLine?

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

    init(showing lines: [LineTrains], from index: Int, laterTrain: Departure? = nil) {
        let firstIndex = lines.indices.contains(index) ? index : 0
        var shown = Array(lines[firstIndex...].prefix(1))
        if shown.flatMap(\.directions).count > Self.maximumRowsWithTwoTrains {
            shown = shown.map(\.keepingOnlyTheNextTrains)
        }
        let soonestTrain = lines
            .flatMap { line in
                line.directions.compactMap { direction in
                    direction.trains.first.map { train in
                        SoonestTrain(line: line.line, train: train)
                    }
                }
            }
            .min { $0.time < $1.time }
        let nextTrainIsOverAnHourAway = soonestTrain == nil
            && lines.contains { $0.directions.contains(where: \.nextTrainIsOverAnHourAway) }
        self.init(
            lines: shown,
            allLines: lines.map(\.line),
            firstIndex: firstIndex,
            soonestTrain: soonestTrain,
            nextTrainIsOverAnHourAway: nextTrainIsOverAnHourAway
        )
        lineWithNoAnswer = lines.first { $0.directions.contains(where: \.hasNoAnswer) }?.line
        if nextTrainIsOverAnHourAway {
            nextTrainComesWithinTheHourAt = laterTrain?.time.addingTimeInterval(-DepartureBoard.farthestTimeSeconds)
            lineOfTheTrainOverAnHourAway = laterTrain.flatMap { train in
                lines.first { $0.line.mode == train.line.mode && $0.line.name == train.line.name }?.line
            }
        }
    }

    func nextRedrawDate(after now: Date) -> Date? {
        let trainDates = lines.flatMap { line in
            line.directions.flatMap(\.shownTrains).flatMap { train in
                PlatformStatus.changeDates(arrival: train.arrivalTime, departure: train.time)
            }
        }
        return (trainDates + (soonestTrain?.redrawDates ?? [])).filter { $0 > now }.min()
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
