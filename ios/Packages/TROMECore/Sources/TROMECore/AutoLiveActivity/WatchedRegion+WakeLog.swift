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
        let stop = regions.first { $0.id.hasPrefix(stopPrefix) }
            .map { "; \(label(ofId: $0.id, catalog: catalog))" } ?? ""
        let refresh = regions.first { $0.id == refreshId }.map { "; area around you \(Int($0.radiusMeters)) m" } ?? ""
        guard let nearest = stations.first, let farthest = stations.last else {
            return "Watching no station\(stop)\(refresh)"
        }
        return """
            Watching \(stations.count) stations, from \(nearest.name) (\(nearest.distance) m) \
            to \(farthest.name) (\(farthest.distance) m)\(stop)\(refresh)
            """
    }
}

#if DEBUG
extension WatchedRegion {
    /// The label of a station area with where the phone was when iOS sent its event: how far from the centre
    /// of the station (the point that the arrival rules measure from), and how accurate and how old the position
    /// that iOS had then was. A walk reads from it how far from the station, and how late, iOS woke the app.
    /// Only the Wake log of debug builds uses it.
    public static func wakeLabel(
        ofId id: String, phoneAt fix: PositionFix?, now: Date, catalog: StationCatalog
    ) -> String {
        let label = label(ofId: id, catalog: catalog)
        guard let station = stationId(inRegionId: id).flatMap(catalog.station(withId:)) else { return label }
        guard let fix else { return "\(label) (iOS gave no position)" }
        let distance = Int(fix.coordinate.distance(to: station.coordinate))
        let age = max(0, Int(now.timeIntervalSince(fix.timestamp)))
        return "\(label) (phone \(distance) m away, ±\(Int(fix.accuracyMeters)) m, \(age) s old)"
    }

    static func stationId(inRegionId id: String) -> String? {
        if let stationId = arrivalStationId(inRegionId: id) {
            return stationId
        }
        return id.hasPrefix(stopPrefix) ? String(id.dropFirst(stopPrefix.count)) : nil
    }
}
#endif
