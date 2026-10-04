import Foundation
import TROMECore

extension LiveActivityRenderCheck {
    typealias StationState = (station: Station, state: StationActivityAttributes.ContentState)

    static let rerStatesStation = "Auber"
    static let firstRERStatesPage = 100

    static func rerStates(at catalog: StationCatalog, now: Date) -> [StationState] {
        func train(_ minutes: Double, _ end: String, _ status: PlatformStatus? = nil) -> LineDirection.Train {
            LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: end, status: status)
        }
        func state(_ lineName: String, at stationName: String, _ directions: [LineDirection]) -> StationState? {
            rerState(of: lineName, at: stationName, in: catalog, directions, now: now)
        }
        let west = "Saint-Germain-en-Laye / Cergy le Haut / Poissy"
        let east = "Boissy-Saint-Léger / Marne-la-Vallée - Chessy"
        let cWest = "Pontoise / Versailles Château Rive Gauche / Saint-Quentin en Yvelines - Montigny-le-Bretonneux"
        let cSouth = "Dourdan la Forêt / Saint-Martin d'Étampes / Massy - Palaiseau"
        return [
            state("A", at: rerStatesStation, [
                LineDirection(label: east, trains: [
                    train(0.4, "Marne-la-Vallée - Chessy", .atPlatform),
                    train(0.8, "Boissy-Saint-Léger", .approaching)
                ]),
                LineDirection(label: west, trains: [train(12, "Saint-Germain-en-Laye"), train(47, "Cergy le Haut")])
            ]),
            state("A", at: rerStatesStation, [
                LineDirection(label: east, trains: []),
                LineDirection(label: west, trains: [], nextTrainIsOverAnHourAway: true)
            ]),
            state("A", at: rerStatesStation, [
                LineDirection(label: east, trains: [train(2, "Boissy-Saint-Léger")]),
                LineDirection(label: west, trains: [train(5, "Poissy")]),
                LineDirection(label: "Nanterre - Préfecture", trains: [train(9, "Nanterre - Préfecture")])
            ]),
            state("C", at: "Invalides", [
                LineDirection(label: cWest, trains: [
                    train(2, "Saint-Quentin en Yvelines - Montigny-le-Bretonneux"),
                    train(7, "Versailles Château Rive Gauche")
                ]),
                LineDirection(label: cSouth, trains: [
                    train(4, "Saint-Martin d'Étampes"),
                    train(12, "Dourdan la Forêt")
                ])
            ])
        ].compactMap { $0 } + rerShortTripStates(at: catalog, now: now)
    }

    private static func rerShortTripStates(at catalog: StationCatalog, now: Date) -> [StationState] {
        func train(_ minutes: Double, _ end: String) -> LineDirection.Train {
            LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: end)
        }
        func state(_ lineName: String, at stationName: String, _ directions: [LineDirection]) -> StationState? {
            rerState(of: lineName, at: stationName, in: catalog, directions, now: now)
        }
        let dSouth = "Melun / Malesherbes"
        return [
            state("D", at: "Châtelet - Les Halles", [
                LineDirection(label: "Creil", trains: [
                    train(2, "Stade de France Saint-Denis"),
                    train(9, "Villiers-le-Bel - Gonesse - Arnouville")
                ]),
                LineDirection(label: dSouth, trains: [train(4, "Melun"), train(11, "Malesherbes")])
            ]),
            state("D", at: "Gare de Lyon", [
                LineDirection(label: "Creil", trains: [train(2, "Goussainville"), train(5, "Orry-la-Ville - Coye")]),
                LineDirection(label: dSouth, trains: [train(3, "Corbeil-Essonnes"), train(7, "Melun")])
            ]),
            state("E", at: "Magenta", [
                LineDirection(label: "Nanterre-La-Folie", trains: [
                    train(2, "Haussmann Saint-Lazare"),
                    train(6, "Nanterre-La-Folie")
                ]),
                LineDirection(label: "Chelles - Gournay / Tournan", trains: [
                    train(3, "Chelles - Gournay"),
                    train(8, "Tournan")
                ])
            ])
        ].compactMap { $0 }
    }

    private static func rerState(
        of lineName: String,
        at stationName: String,
        in catalog: StationCatalog,
        _ directions: [LineDirection],
        now: Date
    ) -> StationState? {
        guard let station = catalog.stations.first(where: { $0.name == stationName }),
              let line = station.lines.first(where: { $0.name == lineName })
        else { return nil }
        return (station, StationActivityAttributes.ContentState(
            stationName: station.name,
            trains: .lines(LinesPage(
                lines: [LineTrains(line: line, directions: directions)],
                allLines: [line],
                firstIndex: 0,
                soonestTrain: nil
            )),
            updatedAt: now
        ))
    }
}
