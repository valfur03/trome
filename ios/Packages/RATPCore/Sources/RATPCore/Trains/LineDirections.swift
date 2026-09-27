import Foundation

public struct LineDirection: Codable, Hashable, Sendable {
    public struct Train: Codable, Hashable, Sendable {
        public var time: Date
        public var destination: String

        public init(time: Date, destination: String) {
            self.time = time
            self.destination = destination
        }
    }

    public var label: String
    public var trains: [Train]

    public init(label: String, trains: [Train]) {
        self.label = label
        self.trains = trains
    }

    public init(label: String, times: [Date]) {
        self.init(label: label, trains: times.map { Train(time: $0, destination: label) })
    }

    public var times: [Date] {
        trains.map(\.time)
    }

    public var showsEachDestination: Bool {
        trains.contains { $0.destination != label }
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
            let sideTrains = groups.filter { $0.side == index }.flatMap(\.trains).sorted { $0.time < $1.time }
            guard showsEmptySides || !sideTrains.isEmpty else { return nil }
            let ends = line.ends?.reachableEnds(of: sides[index], from: station.name) ?? sides[index]
            return LineDirection(
                label: ends.joined(separator: " / "),
                trains: sideTrains.prefix(timesPerDirection).map { train in
                    LineDirection.Train(
                        time: train.time,
                        destination: endName(of: train.destination, in: sides[index]) ?? train.destination
                    )
                }
            )
        }
        let otherDirections = groups
            .filter { $0.side == nil && !$0.trains.isEmpty }
            .sorted { $0.trains[0].time < $1.trains[0].time }
            .map { group in
                LineDirection(
                    label: group.trains[0].destination,
                    trains: group.trains.prefix(timesPerDirection).map {
                        LineDirection.Train(time: $0.time, destination: $0.destination)
                    }
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
        sides.firstIndex { endName(of: destination, in: $0) != nil }
    }

    private static func endName(of destination: String, in names: [String]) -> String? {
        let key = StationCatalog.searchKey(destination)
        return names.first { name in
            let nameKey = StationCatalog.searchKey(name)
            return key == nameKey || key.hasPrefix(nameKey + " ")
        }
    }
}
