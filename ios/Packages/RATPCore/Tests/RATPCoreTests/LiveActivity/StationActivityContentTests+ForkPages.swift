import Foundation
import Testing
@testable import RATPCore

extension StationActivityContentTests {
    static let sizeLimitOfALiveActivity = 4_096
    static let marginLeftForTheForkPages = 0.2

    private func busyDepartures(of line: TransitLine, at station: Station) -> [Departure] {
        guard let ends = line.ends else { return [] }
        let stationKey = StationCatalog.searchKey(station.name)
        return ends.sides.enumerated().flatMap { sideIndex, side -> [Departure] in
            guard !side.contains(where: { StationCatalog.searchKey($0) == stationKey }) else { return [] }
            let destinations = ends.reachableEnds(of: side, from: station.name)
            return (0..<8).map { index in
                let departure = now.addingTimeInterval(TimeInterval(30 + sideIndex * 20 + index * 150))
                return Departure(
                    line: line,
                    destination: destinations[index % destinations.count],
                    time: departure,
                    arrivalTime: departure.addingTimeInterval(-25),
                    isAtStop: index < 2
                )
            }
        }
    }

    @Test(arguments: ["Saint-Lazare", "Opéra", "Auber", "Liège", "Maison Blanche"])
    func keepsEveryPageOfAForkStationWellUnderTheSizeLimitOfALiveActivity(name: String) throws {
        let catalog = try StationCatalog.bundled()
        let station = try #require(catalog.stations.first { $0.name == name })
        let hub = catalog.hubStations(of: station)
        let departures = hub.flatMap { part in part.lines.flatMap { busyDepartures(of: $0, at: part) } }
        let trains = board(departures, at: hub)
        let attributesSize = try JSONEncoder().encode(StationActivityAttributes()).count
        let limit = Double(Self.sizeLimitOfALiveActivity) * (1 - Self.marginLeftForTheForkPages)
        var index = 0
        var forkPages = 0
        repeat {
            let content = ContentState(station: station, trains: trains, now: now, firstLineIndex: index)
            let page = try #require(content.trains.linesPage)
            forkPages += page.lines.flatMap(\.directions).contains { $0.trainsOfEachEnd != nil } ? 1 : 0
            #expect(Double(try JSONEncoder().encode(content).count + attributesSize) < limit)
            index = page.nextFirstIndex
        } while index != 0 && index < 20

        #expect(forkPages >= 1)
    }
}
