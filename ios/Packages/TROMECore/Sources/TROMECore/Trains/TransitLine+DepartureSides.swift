import Foundation

extension TransitLine {
    func departureSides(at station: Station) -> [(index: Int, destinations: [String])] {
        guard let ends else { return [] }
        let stationKey = StationCatalog.searchKey(station.name)
        return ends.sides.enumerated().compactMap { sideIndex, side in
            guard !side.contains(where: { StationCatalog.searchKey($0) == stationKey }) else { return nil }
            let destinations = ends.reachableEnds(of: side, from: station.name)
            return destinations.isEmpty ? nil : (sideIndex, destinations)
        }
    }
}
