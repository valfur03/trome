import Foundation

public struct BranchEndTrains: Codable, Hashable, Sendable {
    public var end: String
    public var trains: [LineDirection.Train]
    public var nextTrainIsOverAnHourAway: Bool

    public init(end: String, trains: [LineDirection.Train], nextTrainIsOverAnHourAway: Bool = false) {
        self.end = end
        self.trains = trains
        self.nextTrainIsOverAnHourAway = nextTrainIsOverAnHourAway
    }
}
