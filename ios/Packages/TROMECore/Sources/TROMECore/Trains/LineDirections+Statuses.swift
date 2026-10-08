import Foundation

extension LineDirections {
    typealias TrainWithStatus = (train: Departure, status: PlatformStatus?)

    static func withStatuses(
        _ trains: [Departure],
        of line: TransitLine,
        at now: Date
    ) -> [TrainWithStatus] {
        let statuses = PlatformStatus.ofEach(trains, at: now, oneTrainPerPlatform: line.mode == .metro)
        return zip(trains, statuses).map { (train: $0, status: $1) }
    }

    static func shown(
        _ train: TrainWithStatus,
        as destination: String? = nil
    ) -> LineDirection.Train {
        LineDirection.Train(
            time: train.train.time,
            destination: destination ?? train.train.destination,
            status: train.status,
            arrivalTime: train.train.arrivalTime
        )
    }
}
