import Foundation
import TROMECore

extension LiveActivityRenderCheck {
    static let serverOutHubStation = "Saint-Lazare"
    static let serverOutNoDataStation = "Abbesses"
    static let firstServerOutStatesPage = 110
    static let firstUpdateTheAppStatesPage = 140

    static func serverOutStates(
        at catalog: StationCatalog,
        hubDepartures: [Departure],
        now: Date
    ) -> [StationState] {
        var samples: [StationState] = []
        if let hubStation = catalog.stations.first(where: { $0.name == serverOutHubStation }) {
            let hub = catalog.hubStations(of: hubStation)
            let board = DepartureBoard(departures: hubDepartures, stations: hub, now: now)
            let state = StationActivityAttributes.ContentState(
                station: hubStation,
                trains: .departures(board, updatedAt: now),
                now: now
            )
            samples.append((hubStation, state))
        }
        if let stripStation = catalog.stations.first(where: { $0.name == stripStatesStation }),
           let stripState = stripStates(at: stripStation, now: now).first {
            samples.append((stripStation, stripState))
        }
        if let rer = rerStates(at: catalog, now: now).first {
            samples.append(rer)
        }
        if let station = catalog.stations.first(where: { $0.name == serverOutNoDataStation }) {
            samples.append((station, .init(stationName: station.name, trains: .noData, updatedAt: now)))
        }
        return samples.map { station, state in
            var state = state
            state.serverIsOut = true
            return (station, state)
        }
    }

    /// The same pages when the server refused the app token: "Update the app", with its icon, in place of the
    /// words of a server that is out.
    static func updateTheAppStates(from serverOutStates: [StationState]) -> [StationState] {
        serverOutStates.map { station, state in
            var state = state
            state.serverIsOut = false
            state.appNeedsUpdate = true
            return (station, state)
        }
    }
}
