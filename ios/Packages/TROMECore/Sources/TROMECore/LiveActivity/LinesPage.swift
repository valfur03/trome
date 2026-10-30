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

    /// The line as its own page draws it: with more than two directions, each keeps only its next train, so that the
    /// page stays under the 160 points of the lock screen.
    var asItsPageDrawsIt: LineTrains {
        directions.count > LinesPage.maximumRowsWithTwoTrains ? keepingOnlyTheNextTrains : self
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
    /// The lines of the first pages, each as its page draws it, in the order of `allLines`: all of them, or the
    /// first ones that fit the push. Only the server's content carries them: one push goes to every rider of the
    /// station, so each lock screen draws from them the page that its rider tapped to (`showingThePage(chosenBy:)`).
    public var pages: [LineTrains]?
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

    init(showing lines: [LineTrains], from index: Int, laterTrain: Departure? = nil, carriesEveryPage: Bool = false) {
        let firstIndex = lines.indices.contains(index) ? index : 0
        let shown = lines[firstIndex...].prefix(1).map(\.asItsPageDrawsIt)
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
        if carriesEveryPage, lines.count > 1 {
            pages = lines.map(\.asItsPageDrawsIt)
        }
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

    /// Whether a row of this page shows fewer trains than the same row of `shown`: a train of that row has left,
    /// and the answer that this page comes from holds no later train to take its place.
    func showsFewerTrainsInARow(than shown: LinesPage) -> Bool {
        let counts = trainCountOfEachRow
        return shown.trainCountOfEachRow.contains { row, count in counts[row, default: 0] < count }
    }

    private struct Row: Hashable {
        var line: TransitLine
        var direction: String
        var end: String?
    }

    private var trainCountOfEachRow: [Row: Int] {
        var counts: [Row: Int] = [:]
        for line in lines {
            for direction in line.directions {
                counts[Row(line: line.line, direction: direction.label), default: 0] += direction.trains.count
                for endTrains in direction.trainsOfEachEnd ?? [] {
                    let row = Row(line: line.line, direction: direction.label, end: endTrains.end)
                    counts[row, default: 0] += endTrains.trains.count
                }
            }
        }
        return counts
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

    /// The page after this one among the pages that the content carries, and the first after the last.
    var nextCarriedIndex: Int? {
        guard let pages, pages.count > 1 else { return nil }
        let next = firstIndex + 1
        return next < pages.count ? next : 0
    }

    func index(of line: TransitLine) -> Int? {
        allLines.firstIndex { $0.mode == line.mode && $0.name == line.name }
    }

    /// The page of the line at `index`, drawn from the pages that the content carries, with the minutes of this
    /// content; nil when the content does not carry it, so that the caller keeps a page that it has.
    func showing(pageAt index: Int) -> LinesPage? {
        guard let pages, pages.indices.contains(index), allLines.indices.contains(index),
              pages[index].line.mode == allLines[index].mode, pages[index].line.name == allLines[index].name else {
            return nil
        }
        var page = self
        page.lines = [pages[index]]
        page.firstIndex = index
        return page
    }

    var keepingOnlyTheNextTrains: LinesPage {
        var page = self
        page.lines = lines.map(\.keepingOnlyTheNextTrains)
        return page
    }
}
