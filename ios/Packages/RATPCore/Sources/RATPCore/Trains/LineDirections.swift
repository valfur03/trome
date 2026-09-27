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

    public var name: String {
        showsEachDestination ? label : trains.first?.destination ?? label
    }

    public var showsEachDestination: Bool {
        Set(trains.map(\.destination)).count > 1
    }
}

enum LineDirections {
    static let timesPerDirection = 2
    static let maximumDirections = 3

    private struct Group {
        let isOneDirection: Bool
        let isStationQuay: Bool
        let trains: [Departure]
        var side: Int?
    }

    static func directions(of line: TransitLine, at station: Station, from departures: [Departure]) -> [LineDirection] {
        let trains = departures
            .filter { $0.line.mode == line.mode && $0.line.name == line.name }
            .sorted { $0.time < $1.time }
        let quays = PRIMStopReference.quayRefs(of: line)
        let stationKey = StationCatalog.searchKey(station.name)
        let ends = line.ends ?? LineEnds(first: [], second: [])
        let sides = ends.sides.filter { names in
            !names.isEmpty && !names.contains { StationCatalog.searchKey($0) == stationKey }
        }
        var groups = groups(of: trains, quays: quays).map { group in
            var group = group
            group.side = group.trains.lazy.compactMap { side(of: $0.destination, in: sides, ends: ends) }.first
                ?? group.trains.lazy.compactMap {
                    sideTowardTheTrunk(of: $0.destination, from: station.name, in: sides, ends: ends)
                }.first
            return group
        }
        inferQuaySides(of: &groups, sideCount: sides.count)
        inferSidesFromDirectionRefs(of: &groups)

        let hasMetroQuayOfUnknownSide = line.mode == .metro
            && groups.contains { $0.isOneDirection && $0.side == nil && !$0.trains.isEmpty }
        let showsEmptySides = quays.count != 1 && !hasMetroQuayOfUnknownSide
        let sideDirections = sides.indices.compactMap { index -> LineDirection? in
            let sideTrains = groups.filter { $0.side == index }.flatMap(\.trains).sorted { $0.time < $1.time }
            guard showsEmptySides || !sideTrains.isEmpty else { return nil }
            return LineDirection(
                label: ends.reachableEnds(of: sides[index], from: station.name).joined(separator: " / "),
                trains: sideTrains.prefix(timesPerDirection).map { train in
                    LineDirection.Train(
                        time: train.time,
                        destination: endName(of: train.destination, in: sides[index], ends: ends) ?? train.destination
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
        var allQuays = quays
        for train in trains {
            if let quay = train.quayRef, !allQuays.contains(quay) {
                allQuays.append(quay)
            }
        }
        let quayGroups = allQuays.map { quay in
            Group(
                isOneDirection: true,
                isStationQuay: quays.contains(quay),
                trains: trains.filter { $0.quayRef == quay }
            )
        }
        var destinations: [String] = []
        for train in trains where train.quayRef == nil && !destinations.contains(train.destination) {
            destinations.append(train.destination)
        }
        let destinationGroups = destinations.map { destination in
            Group(
                isOneDirection: false,
                isStationQuay: false,
                trains: trains.filter { $0.quayRef == nil && $0.destination == destination }
            )
        }
        return quayGroups + destinationGroups
    }

    private static func inferSidesFromDirectionRefs(of groups: inout [Group]) {
        let directionRefs = Set(groups.flatMap(\.trains).compactMap(\.directionRef))
        guard directionRefs.count > 1 else { return }
        var sidesByDirectionRef: [String: Set<Int>] = [:]
        for group in groups {
            guard let side = group.side else { continue }
            for directionRef in group.trains.compactMap(\.directionRef) {
                sidesByDirectionRef[directionRef, default: []].insert(side)
            }
        }
        for index in groups.indices where groups[index].side == nil {
            let groupSides = groups[index].trains.map { train in
                train.directionRef.flatMap { sidesByDirectionRef[$0] }
            }
            guard let first = groupSides.first,
                  let sides = first, sides.count == 1,
                  groupSides.allSatisfy({ $0 == sides })
            else { continue }
            groups[index].side = sides.first
        }
    }

    private static func inferQuaySides(of groups: inout [Group], sideCount: Int) {
        let unknown = groups.indices.filter { index in
            groups[index].isOneDirection && groups[index].side == nil && !groups[index].trains.isEmpty
        }
        if sideCount == 1 {
            unknown.forEach { groups[$0].side = 0 }
            return
        }
        let freeSides = Set(0..<sideCount).subtracting(groups.compactMap(\.side))
        guard unknown.count == 1, groups[unknown[0]].isStationQuay,
              freeSides.count == 1, let freeSide = freeSides.first
        else { return }
        groups[unknown[0]].side = freeSide
    }

    private static func side(of destination: String, in sides: [[String]], ends: LineEnds) -> Int? {
        sides.firstIndex { endName(of: destination, in: $0, ends: ends) != nil }
    }

    private static func sideTowardTheTrunk(
        of destination: String,
        from stationName: String,
        in sides: [[String]],
        ends: LineEnds
    ) -> Int? {
        let stationKey = StationCatalog.searchKey(stationName)
        let branchSides = ends.sides.indices.filter { index in
            ends.sides[index].contains { end in
                ends.branchStations[end, default: []].contains { StationCatalog.searchKey($0) == stationKey }
            }
        }
        let branchNames = ends.branchStations.values.flatMap { $0 }
        guard branchSides.count == 1, let branchSide = branchSides.first,
              !branchNames.contains(where: { isNamed(destination, $0) })
        else { return nil }
        return sides.firstIndex(of: ends.sides[1 - branchSide])
    }

    private static func endName(of destination: String, in names: [String], ends: LineEnds) -> String? {
        names.lazy
            .flatMap { [$0] + ends.otherNames[$0, default: []] }
            .first { isNamed(destination, $0) }
    }

    private static func isNamed(_ destination: String, _ name: String) -> Bool {
        let key = StationCatalog.searchKey(destination)
        let nameKey = StationCatalog.searchKey(name)
        return key == nameKey || key.hasPrefix(nameKey + " ")
    }
}
