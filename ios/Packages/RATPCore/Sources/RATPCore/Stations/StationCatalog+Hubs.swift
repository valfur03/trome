import Foundation

extension StationCatalog {
    public func hubStations(of station: Station) -> [Station] {
        guard let hubId = station.hubId else { return [station] }
        let linkedStations = stations
            .filter { $0.hubId == hubId && $0.id != station.id }
            .sorted { station.coordinate.distance(to: $0.coordinate) < station.coordinate.distance(to: $1.coordinate) }
        var servedLines = Set(station.lines.map(\.key))
        var hub = [station]
        for linkedStation in linkedStations {
            var part = linkedStation
            part.lines = linkedStation.lines.filter { servedLines.insert($0.key).inserted }
            if !part.lines.isEmpty {
                hub.append(part)
            }
        }
        return hub
    }
}

private extension TransitLine {
    var key: String {
        "\(mode.rawValue)-\(name)"
    }
}
