import Foundation

extension LineDirections {
    static func direction(
        of line: TransitLine,
        toward side: [String],
        from station: Station,
        trains sideTrains: [Departure],
        now: Date
    ) -> LineDirection {
        let ends = line.ends ?? LineEnds(first: [], second: [])
        let reachableEnds = ends.reachableEnds(of: side, from: station.name)
        let branchEnds = line.mode == .metro && reachableEnds.count > 1 ? reachableEnds : nil
        let trains = withStatuses(sideTrains, of: line, at: now)
        return LineDirection(
            label: reachableEnds.joined(separator: " / "),
            trains: trains.prefix(timesPerDirection).map { train in
                shown(train, as: endName(of: train.train.destination, in: side, ends: ends))
            },
            branchEnds: branchEnds,
            trainsOfEachEnd: branchEnds.map { trainsOfEachEnd($0, from: trains, ends: ends) }
        )
    }

    private static func trainsOfEachEnd(
        _ reachableEnds: [String],
        from sideTrains: [TrainWithStatus],
        ends: LineEnds
    ) -> [BranchEndTrains] {
        reachableEnds.map { end in
            BranchEndTrains(
                end: end,
                trains: sideTrains
                    .filter { endName(of: $0.train.destination, in: [end], ends: ends) != nil }
                    .prefix(timesPerDirection)
                    .map { shown($0, as: end) }
            )
        }
    }

    static func markEndsWhoseNextTrainIsOverAnHourAway(
        of direction: inout LineDirection,
        knowing withLaterTrains: LineDirection
    ) {
        guard var endTrains = direction.trainsOfEachEnd,
              let laterEndTrains = withLaterTrains.trainsOfEachEnd
        else { return }
        let laterTrainsTellTheEnds = laterEndTrains.contains { !$0.trains.isEmpty }
        for index in endTrains.indices where endTrains[index].trains.isEmpty {
            let end = endTrains[index].end
            let laterTrainOfTheEnd = laterEndTrains.contains { $0.end == end && !$0.trains.isEmpty }
            endTrains[index].nextTrainIsOverAnHourAway = laterTrainOfTheEnd
                || (!laterTrainsTellTheEnds && direction.nextTrainIsOverAnHourAway)
        }
        direction.trainsOfEachEnd = endTrains
    }
}
