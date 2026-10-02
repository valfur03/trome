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
        return LineDirection(
            label: reachableEnds.joined(separator: " / "),
            trains: sideTrains.prefix(timesPerDirection).map { train in
                shown(train, at: now, as: endName(of: train.destination, in: side, ends: ends))
            },
            branchEnds: branchEnds,
            trainsOfEachEnd: branchEnds.map { trainsOfEachEnd($0, from: sideTrains, ends: ends, now: now) }
        )
    }

    private static func trainsOfEachEnd(
        _ reachableEnds: [String],
        from sideTrains: [Departure],
        ends: LineEnds,
        now: Date
    ) -> [BranchEndTrains] {
        reachableEnds.map { end in
            BranchEndTrains(
                end: end,
                trains: sideTrains
                    .filter { endName(of: $0.destination, in: [end], ends: ends) != nil }
                    .prefix(timesPerDirection)
                    .map { shown($0, at: now, as: end) }
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
        let ends = endTrains.map(\.end)
        let laterTrainsTellTheEnd = withLaterTrains.trains.allSatisfy { ends.contains($0.destination) }
        for index in endTrains.indices where endTrains[index].trains.isEmpty {
            let laterTrainOfTheEnd = laterEndTrains.contains { $0.end == ends[index] && !$0.trains.isEmpty }
            endTrains[index].nextTrainIsOverAnHourAway = laterTrainOfTheEnd
                || (!laterTrainsTellTheEnd && direction.nextTrainIsOverAnHourAway)
        }
        direction.trainsOfEachEnd = endTrains
    }
}
