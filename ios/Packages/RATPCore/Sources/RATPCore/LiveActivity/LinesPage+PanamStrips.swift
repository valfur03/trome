extension LinesPage {
    public var panamStripsLine: LineTrains? {
        guard lines.count == 1, let line = lines.first,
              line.line.mode == .metro,
              line.directions.count <= 2,
              line.hasADirectionWithTwoEnds != nil,
              line.directions.allSatisfy(\.fitsAPanamStrip)
        else { return nil }
        return line
    }
}

extension LineDirection {
    public func branchEndIndex(of train: Train) -> Int? {
        branchEnds?.firstIndex(of: train.destination)
    }

    var fitsAPanamStrip: Bool {
        guard branchEnds != nil else { return !showsEachDestination }
        return trains.allSatisfy { branchEndIndex(of: $0) != nil }
    }
}

extension LineTrains {
    public var hasRoomForATwoLineStationName: Bool {
        directions.count <= 1
    }
}
