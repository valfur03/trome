public struct BranchEndRow: Hashable, Sendable {
    public enum Shown: Hashable, Sendable {
        case trains([LineDirection.Train])
        case notListed
        case overAnHour
        case noTrain
    }

    public var end: String
    public var shown: Shown
}

extension LineDirection {
    public var branchEndRows: [BranchEndRow]? {
        trainsOfEachEnd?.map { endTrains in
            BranchEndRow(end: endTrains.end, shown: shown(for: endTrains))
        }
    }

    private func shown(for endTrains: BranchEndTrains) -> BranchEndRow.Shown {
        if !endTrains.trains.isEmpty {
            return .trains(endTrains.trains)
        }
        if endTrains.nextTrainIsOverAnHourAway {
            return .overAnHour
        }
        return listsNoTrain ? .noTrain : .notListed
    }

    private var listsNoTrain: Bool {
        trains.isEmpty && !nextTrainIsOverAnHourAway
            && !(trainsOfEachEnd ?? []).contains(where: \.nextTrainIsOverAnHourAway)
    }
}
