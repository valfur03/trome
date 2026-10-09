#if DEBUG
import os
import TROMECore

extension FakeTrainsLaunch {
    nonisolated private static let logger = Logger(category: "FakeTrains")

    func log(hasTrainDataKey: Bool) {
        Self.logger.notice("\(logLine(hasTrainDataKey: hasTrainDataKey), privacy: .public)")
    }
}
#endif
