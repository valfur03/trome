import Foundation

public struct LineTrains: Codable, Hashable, Sendable {
    public var line: TransitLine
    public var directions: [LineDirection]

    public init(line: TransitLine, directions: [LineDirection]) {
        self.line = line
        self.directions = directions
    }

    var rowCount: Int {
        max(1, directions.count)
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

    public init(lines: [LineTrains], allLines: [TransitLine], firstIndex: Int, soonestTrain: SoonestTrain?) {
        self.lines = lines
        self.allLines = allLines
        self.firstIndex = firstIndex
        self.soonestTrain = soonestTrain
    }

    init(showing lines: [LineTrains], from index: Int) {
        let firstIndex = lines.indices.contains(index) ? index : 0
        var shown: [LineTrains] = []
        var rowCount = 0
        for line in lines[firstIndex...] {
            guard shown.isEmpty || rowCount + line.rowCount <= Self.maximumRows else { break }
            shown.append(line)
            rowCount += line.rowCount
        }
        if shown.flatMap(\.directions).count > Self.maximumRowsWithTwoTrains {
            shown = shown.map { line in
                LineTrains(
                    line: line.line,
                    directions: line.directions.map { direction in
                        LineDirection(label: direction.label, trains: Array(direction.trains.prefix(1)))
                    }
                )
            }
        }
        self.init(
            lines: shown,
            allLines: lines.map(\.line),
            firstIndex: firstIndex,
            soonestTrain: lines
                .flatMap { line in line.directions.compactMap(\.trains.first).map { (line: line.line, time: $0.time) } }
                .min { $0.time < $1.time }
                .map { SoonestTrain(line: $0.line, time: $0.time) }
        )
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

    public func isShown(_ line: TransitLine) -> Bool {
        lines.contains { $0.line == line }
    }
}
