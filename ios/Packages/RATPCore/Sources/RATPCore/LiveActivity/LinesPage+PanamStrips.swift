extension LinesPage {
    public var panamStripsLine: LineTrains? {
        guard allLines.count == 1, lines.count == 1, let line = lines.first,
              line.line.mode == .metro,
              line.stationName == nil,
              line.directions.count <= 2,
              line.hasADirectionWithTwoEnds == false,
              !line.directions.contains(where: \.showsEachDestination)
        else { return nil }
        return line
    }
}
