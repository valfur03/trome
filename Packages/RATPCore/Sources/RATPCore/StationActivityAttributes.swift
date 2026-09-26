import Foundation

public struct StationActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var updatedAt: Date

        public init(updatedAt: Date) {
            self.updatedAt = updatedAt
        }
    }

    public var stationName: String

    public init(stationName: String) {
        self.stationName = stationName
    }
}

#if os(iOS)
import ActivityKit

extension StationActivityAttributes: ActivityAttributes {}
#endif
