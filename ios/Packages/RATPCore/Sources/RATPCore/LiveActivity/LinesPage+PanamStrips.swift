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
    var fitsAPanamStrip: Bool {
        guard let branchEnds else { return !showsEachDestination }
        return trains.allSatisfy { branchEnds.contains($0.destination) }
    }

    var shownTrains: [Train] {
        trains + (trainsOfEachEnd ?? []).flatMap(\.trains)
    }
}

extension LineTrains {
    public var hasRoomForATwoLineStationName: Bool {
        directions.count <= 1
    }
}
