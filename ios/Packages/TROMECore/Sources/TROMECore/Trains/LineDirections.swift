import Foundation

public struct LineDirection: Codable, Hashable, Sendable {
    public struct Train: Codable, Hashable, Sendable {
        public var time: Date
        public var destination: String
        public var status: PlatformStatus?
        public var arrivalTime: Date?

        public init(time: Date, destination: String, status: PlatformStatus? = nil, arrivalTime: Date? = nil) {
            self.time = time
            self.destination = destination
            self.status = status
            self.arrivalTime = arrivalTime
        }

        /// The moment when the wait of this train reaches "0" on the Live Activity, which shows the whole minutes left
        /// until it (rounded down), and holds "0" after it.
        ///
        /// A metro wait counts down to the train time, so it reads 3, 2, 1, 0 like the platform screens of the metro,
        /// and its "0" (under a minute) agrees with the status "approaching" (arrival under 60 s), as PRIM gives a
        /// metro train the same arrival and departure. So it is never more than the real wait.
        /// An RER wait counts down to the train time + 60 s, so it reads the minutes rounded up and never "0" while the
        /// train has not left: an RER row says "Approaching" in its last minute, a word that only the app can draw,
        /// and a closed app cannot draw it in time.
        public func countdownEnd(on mode: TransitMode) -> Date {
            switch mode {
            case .metro: time
            case .rer: time.addingTimeInterval(60)
            }
        }

        /// The number that the wait of this train reads at `now`: the whole minutes left until its countdown end.
        /// An RER wait never reads 0 (see `countdownEnd(on:)`).
        public func countdownMinutes(at now: Date, on mode: TransitMode) -> Int {
            let minutes = DepartureTime.minutes(until: countdownEnd(on: mode), from: now)
            return switch mode {
            case .metro: minutes
            case .rer: max(1, minutes)
            }
        }
    }

    public var label: String
    public var trains: [Train]
    public var nextTrainIsOverAnHourAway: Bool
    public var branchEnds: [String]?
    public var trainsOfEachEnd: [BranchEndTrains]?
    var noAnswer: Bool?

    public init(
        label: String,
        trains: [Train],
        nextTrainIsOverAnHourAway: Bool = false,
        branchEnds: [String]? = nil,
        trainsOfEachEnd: [BranchEndTrains]? = nil,
        hasNoAnswer: Bool = false
    ) {
        self.label = label
        self.trains = trains
        self.nextTrainIsOverAnHourAway = nextTrainIsOverAnHourAway
        self.branchEnds = branchEnds
        self.trainsOfEachEnd = trainsOfEachEnd
        self.noAnswer = hasNoAnswer ? true : nil
    }

    /// Whether the stop of this direction did not answer while another stop of the station did:
    /// the app does not know its trains, so it shows an empty box, never "no train".
    public var hasNoAnswer: Bool {
        noAnswer ?? false
    }

    public init(label: String, times: [Date], nextTrainIsOverAnHourAway: Bool = false) {
        self.init(
            label: label,
            trains: times.map { Train(time: $0, destination: label) },
            nextTrainIsOverAnHourAway: nextTrainIsOverAnHourAway
        )
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

    public var trainsByDestination: [DestinationTrains] {
        guard showsEachDestination else {
            return [DestinationTrains(destination: name, trains: trains)]
        }
        var groups: [DestinationTrains] = []
        for train in trains {
            if let index = groups.firstIndex(where: { $0.destination == train.destination }) {
                groups[index].trains.append(train)
            } else {
                groups.append(DestinationTrains(destination: train.destination, trains: [train]))
            }
        }
        return groups
    }
}

public struct DestinationTrains: Hashable, Sendable {
    public var destination: String
    public var trains: [LineDirection.Train]
}

enum LineDirections {
    static let timesPerDirection = 2
    static let maximumDirections = 3
    static let minimumMetroHeadway: TimeInterval = 60

    private struct Group {
        let isOneDirection: Bool
        let isStationQuay: Bool
        let trains: [Departure]
        var side: Int?
    }

    static func directions(
        of line: TransitLine,
        at station: Station,
        from departures: [Departure],
        later laterDepartures: [Departure] = [],
        now: Date
    ) -> [LineDirection] {
        var shown = directions(of: line, at: station, trainsFrom: departures, now: now)
        guard !laterDepartures.isEmpty else { return shown }
        let laterTimes = Set(laterDepartures.map(\.time))
        let withLater = directions(of: line, at: station, trainsFrom: departures + laterDepartures, now: now)
        let laterOnly = withLater
            .filter { direction in direction.trains.first.map { laterTimes.contains($0.time) } ?? false }
        for later in laterOnly {
            if let index = shown.firstIndex(where: { $0.label == later.label }) {
                if shown[index].trains.isEmpty {
                    shown[index].nextTrainIsOverAnHourAway = true
                }
            } else if shown.count < maximumDirections {
                shown.append(LineDirection(
                    label: later.label,
                    trains: [],
                    nextTrainIsOverAnHourAway: true,
                    branchEnds: later.branchEnds,
                    trainsOfEachEnd: later.trainsOfEachEnd?.map { BranchEndTrains(end: $0.end, trains: []) }
                ))
            }
        }
        for index in shown.indices {
            guard let later = withLater.first(where: { $0.label == shown[index].label }) else { continue }
            markEndsWhoseNextTrainIsOverAnHourAway(of: &shown[index], knowing: later)
        }
        return shown
    }

    static func directions(
        of line: TransitLine,
        at station: Station,
        trainsFrom departures: [Departure],
        now: Date,
        showsEverySide: Bool = false
    ) -> [LineDirection] {
        let trains = departures
            .filter { $0.line.mode == line.mode && $0.line.name == line.name }
            .sorted { $0.time < $1.time }
        let quays = PRIMStopReference.quayRefs(of: line)
        let stationKey = StationCatalog.searchKey(station.name)
        let ends = line.ends ?? LineEnds(first: [], second: [])
        let sides = ends.sides.filter { names in
            !names.isEmpty && !names.contains { StationCatalog.searchKey($0) == stationKey }
        }
        let isOnTheRERTrunk = line.mode == .rer && sides.count == 2 && !ends.branchStations.values.contains { names in
            names.contains { StationCatalog.searchKey($0) == stationKey }
        }
        var groups = groups(of: trains, quays: quays).map { group in
            var group = group
            group.side = side(of: group, at: station, in: sides, ends: ends, isOnTheRERTrunk: isOnTheRERTrunk)
            return group
        }
        inferQuaySides(of: &groups, sideCount: sides.count)
        inferSidesFromDirectionRefs(of: &groups)

        let hasMetroQuayOfUnknownSide = line.mode == .metro
            && groups.contains { $0.isOneDirection && $0.side == nil && !$0.trains.isEmpty }
        let showsEmptySides = showsEverySide || (quays.count != 1 && !hasMetroQuayOfUnknownSide)
        let sideDirections = sides.indices.compactMap { index -> LineDirection? in
            let sideTrains = oneEntryPerTrain(
                groups.filter { $0.side == index }.flatMap(\.trains).sorted { $0.time < $1.time },
                of: line
            )
            guard showsEmptySides || !sideTrains.isEmpty else { return nil }
            return direction(of: line, toward: sides[index], from: station, trains: sideTrains, now: now)
        }
        let otherDirections = groups
            .filter { $0.side == nil && !$0.trains.isEmpty && !isOnTheRERTrunk }
            .sorted { $0.trains[0].time < $1.trains[0].time }
            .map { group in
                LineDirection(
                    label: group.trains[0].destination,
                    trains: withStatuses(oneEntryPerTrain(group.trains, of: line), of: line, at: now)
                        .prefix(timesPerDirection)
                        .map { shown($0) }
                )
            }
        return Array((sideDirections + otherDirections).prefix(maximumDirections))
    }

    private static func oneEntryPerTrain(_ trains: [Departure], of line: TransitLine) -> [Departure] {
        guard line.mode == .metro else { return trains }
        var kept: [Departure] = []
        for train in trains {
            if let last = kept.last, train.time.timeIntervalSince(last.time) < minimumMetroHeadway {
                continue
            }
            kept.append(train)
        }
        return kept
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

    private static func side(
        of group: Group,
        at station: Station,
        in sides: [[String]],
        ends: LineEnds,
        isOnTheRERTrunk: Bool
    ) -> Int? {
        let destinations = group.trains.lazy.map(\.destination)
        if let side = destinations.compactMap({ side(of: $0, in: sides, ends: ends) }).first {
            return side
        }
        if let side = destinations.compactMap({
            sideTowardTheTrunk(of: $0, from: station.name, in: sides, ends: ends)
        }).first {
            return side
        }
        guard isOnTheRERTrunk else { return nil }
        return destinations.compactMap { destination in
            ends.trunkSide(of: destination, from: station.name).flatMap { sides.firstIndex(of: $0) }
                ?? sideOfTheBranches(naming: destination, in: sides, ends: ends)
        }.first
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
        func branchHoldsTheStation(_ end: String) -> Bool {
            ends.branchStations[end, default: []].contains { StationCatalog.searchKey($0) == stationKey }
        }
        func branchHoldsTheDestination(_ end: String) -> Bool {
            ends.branchStations[end, default: []].contains { isNamed(destination, $0) }
        }
        let branchSides = ends.sides.indices.filter { ends.sides[$0].contains(where: branchHoldsTheStation) }
        guard branchSides.count == 1, let branchSide = branchSides.first else { return nil }
        let sideEnds = ends.sides[branchSide]
        let isOnNoBranch = !ends.branchStations.keys.contains(where: branchHoldsTheDestination)
        let stationEnds = sideEnds.filter(branchHoldsTheStation)
        let otherEnds = sideEnds.filter { !branchHoldsTheStation($0) }
        let isBeforeTheForkOfTheStation = stationEnds.contains(where: branchHoldsTheDestination)
            && otherEnds.contains(where: branchHoldsTheDestination)
        guard isOnNoBranch || isBeforeTheForkOfTheStation else { return nil }
        return sides.firstIndex(of: ends.sides[1 - branchSide])
    }

    private static func sideOfTheBranches(naming destination: String, in sides: [[String]], ends: LineEnds) -> Int? {
        let namingSides = sides.indices.filter { index in
            sides[index].contains { end in
                ends.branchStations[end, default: []].contains { isNamed(destination, $0) }
            }
        }
        return namingSides.count == 1 ? namingSides.first : nil
    }

    static func endName(of destination: String, in names: [String], ends: LineEnds) -> String? {
        names.lazy
            .flatMap { [$0] + ends.otherNames[$0, default: []] }
            .first { isNamed(destination, $0) }
    }

    static func isNamed(_ destination: String, _ name: String) -> Bool {
        let key = StationCatalog.searchKey(destination)
        let nameKey = StationCatalog.searchKey(name)
        return key == nameKey || key.hasPrefix(nameKey + " ")
    }
}
