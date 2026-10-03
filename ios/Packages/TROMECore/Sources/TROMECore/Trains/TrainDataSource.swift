import Foundation

public enum TrainDataSource: Equatable, Sendable {
    case prim(apiKey: String)
    case server(TrainServerConfiguration)
}
