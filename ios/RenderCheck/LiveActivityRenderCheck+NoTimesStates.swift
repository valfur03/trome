import Foundation
import TROMECore

extension LiveActivityRenderCheck {
    static let noTimesStation = "Abbesses"
    static let firstNoTimesStatesPage = 120

    static func noTimesStates(at catalog: StationCatalog, now: Date) -> [StationState] {
        guard let station = catalog.stations.first(where: { $0.name == noTimesStation }) else { return [] }
        return [StationActivityAttributes.Trains.loading, .noData].map { trains in
            (station, .init(stationName: station.name, trains: trains, updatedAt: now))
        }
    }
}
