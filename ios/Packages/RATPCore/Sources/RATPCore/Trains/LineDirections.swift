import Foundation

public struct LineDirection: Codable, Hashable, Sendable {
    public var label: String
    public var times: [Date]

    public init(label: String, times: [Date]) {
        self.label = label
        self.times = times
    }
}

enum LineDirections {
    static let timesPerDirection = 2
    static let maximumDirections = 3

    private struct Group {
        let isQuay: Bool
        let trains: [Departure]
        var side: Int?
    }

    static func directions(of line: TransitLine, at station: Station, from departures: [Departure]) -> [LineDirection] {
        let trains = departures
            .filter { $0.line.mode == line.mode && $0.line.name == line.name }
            .sorted { $0.time < $1.time }
        let quays = PRIMStopReference.quayRefs(of: line)
        let stationKey = StationCatalog.searchKey(station.name)
        let sides = (line.ends?.sides ?? []).filter { names in
            !names.contains { StationCatalog.searchKey($0) == stationKey }
        }
        var groups = groups(of: trains, quays: quays).map { group in
            var group = group
            group.side = group.trains.lazy.compactMap { side(of: $0.destination, in: sides) }.first
            return group
        }
        inferQuaySides(of: &groups, sideCount: sides.count)

        let showsEmptySides = quays.count != 1
        let sideDirections = sides.indices.compactMap { index -> LineDirection? in
            let times = groups.filter { $0.side == index }.flatMap(\.trains).map(\.time).sorted()
            guard showsEmptySides || !times.isEmpty else { return nil }
            return LineDirection(
                label: sides[index].joined(separator: " / "),
                times: Array(times.prefix(timesPerDirection))
            )
        }
        let otherDirections = groups
            .filter { $0.side == nil && !$0.trains.isEmpty }
            .sorted { $0.trains[0].time < $1.trains[0].time }
            .map { group in
                LineDirection(
                    label: group.trains[0].destination,
                    times: Array(group.trains.map(\.time).prefix(timesPerDirection))
                )
            }
        return Array((sideDirections + otherDirections).prefix(maximumDirections))
    }

    private static func groups(of trains: [Departure], quays: [String]) -> [Group] {
        let quayGroups = quays.map { quay in
            Group(isQuay: true, trains: trains.filter { $0.quayRef == quay })
        }
        var destinations: [String] = []
        for train in trains where !quays.contains(train.quayRef ?? "") && !destinations.contains(train.destination) {
            destinations.append(train.destination)
        }
        let destinationGroups = destinations.map { destination in
            Group(
                isQuay: false,
                trains: trains.filter { !quays.contains($0.quayRef ?? "") && $0.destination == destination }
            )
        }
        return quayGroups + destinationGroups
    }

    private static func inferQuaySides(of groups: inout [Group], sideCount: Int) {
        let unknown = groups.indices.filter { index in
            groups[index].isQuay && groups[index].side == nil && !groups[index].trains.isEmpty
        }
        if sideCount == 1 {
            unknown.forEach { groups[$0].side = 0 }
            return
        }
        let freeSides = Set(0..<sideCount).subtracting(groups.compactMap(\.side))
        guard unknown.count == 1, freeSides.count == 1, let freeSide = freeSides.first else { return }
        groups[unknown[0]].side = freeSide
    }

    private static func side(of destination: String, in sides: [[String]]) -> Int? {
        let key = StationCatalog.searchKey(destination)
        return sides.firstIndex { names in
            names.contains { name in
                let nameKey = StationCatalog.searchKey(name)
                return key == nameKey || key.hasPrefix(nameKey + " ")
            }
        }
    }
}
