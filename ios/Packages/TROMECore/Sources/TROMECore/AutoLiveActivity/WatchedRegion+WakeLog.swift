import Foundation

extension WatchedRegion {
    public static func label(ofId id: String, catalog: StationCatalog) -> String {
        if let stationId = arrivalStationId(inRegionId: id) {
            return catalog.station(withId: stationId)?.name ?? id
        }
        if id.hasPrefix(stopPrefix) {
            let name = catalog.station(withId: String(id.dropFirst(stopPrefix.count)))?.name ?? id
            return "stop area of \(name)"
        }
        if id == refreshId {
            return "area around you"
        }
        return id
    }

    static func summary(of regions: [WatchedRegion], around position: Coordinate, catalog: StationCatalog) -> String {
        let stations = regions
            .compactMap { arrivalStationId(inRegionId: $0.id).flatMap(catalog.station(withId:)) }
            .map { (name: $0.name, distance: Int(position.distance(to: $0.coordinate))) }
        let refresh = regions.first { $0.id == refreshId }.map { "; area around you \(Int($0.radiusMeters)) m" } ?? ""
        guard let nearest = stations.first, let farthest = stations.last else {
            return "Watching no station\(refresh)"
        }
        return """
            Watching \(stations.count) stations, from \(nearest.name) (\(nearest.distance) m) \
            to \(farthest.name) (\(farthest.distance) m)\(refresh)
            """
    }
}
