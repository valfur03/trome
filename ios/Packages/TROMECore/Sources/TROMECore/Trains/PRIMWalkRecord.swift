import Foundation

/// The few PRIM entries that the walk record (`WakeLog`) keeps, with all their fields, so that a row that should not
/// be there, or a train that should, can be explained from the record of a walk alone.
/// Two cases, each a group of lines for one station, and nothing else from PRIM:
/// - two entries that the app keeps in one row of a line (one side of the station) under 60 s apart: the screen
///   shows whole minutes, so two rows that read the same minute prove only that;
/// - an entry that PRIM says is at the platform, whose time has passed: the Live Activity hides it.
/// Each entry is written as the debug log writes it (`PRIMAnswerLog`): what the app does with it, its fields, and
/// the time of the call and of the answer; a pair adds the minutes that each entry shows.
public enum PRIMWalkRecord {
    /// The two entries of a row are a pair when they are less than this apart.
    static let pairSpacing: TimeInterval = 60

    /// The two cases. The record bounds the groups of each case apart (`WakeLog.maximumPRIMGroups(of:)`), so that
    /// the many stations where a train stands past its time never push out the rare pair that a walk caught.
    public enum Case: Sendable, CaseIterable {
        case pair
        case standing

        /// The start of the first line of each group of this case.
        public var title: String {
            switch self {
            case .pair: "PRIM, two entries under 60 s apart"
            case .standing: "PRIM, at the platform past its time"
            }
        }
    }

    public struct Group: Equatable, Sendable {
        public let `case`: Case
        public let station: String
        public let lines: [String]

        public init(_ case: Case, at station: String, lines: [String]) {
            self.case = `case`
            self.station = station
            self.lines = lines
        }

        /// The first line of the group: its case and its station, so that the record writes each case once per
        /// station and hour.
        public var title: String {
            "\(self.case.title): \(station)"
        }

        public var text: String {
            ([title] + lines).joined(separator: "\n")
        }
    }

    private struct Kept {
        let entry: PRIMAnswerLog.Entry
        let departure: Departure
    }

    static func groups(
        of answers: [PRIMDeparturesProvider.Answer],
        at stations: [Station],
        now: Date,
        timeZone: TimeZone = .current
    ) -> [Group] {
        let kept = PRIMAnswerLog.calls(of: answers, at: stations, now: now, timeZone: timeZone)
            .flatMap(\.entries)
            .compactMap { entry -> Kept? in
                guard case .kept(let departure) = entry.outcome else { return nil }
                return Kept(entry: entry, departure: departure)
            }
        var linesSeen: Set<String> = []
        return stations.flatMap { station -> [Group] in
            let lines = station.lines.filter { linesSeen.insert(key(of: $0)).inserted }
            let keptHere = kept.filter { item in lines.contains { key(of: $0) == key(of: item.departure.line) } }
            return [
                pairGroup(of: keptHere, lines: lines, at: station, now: now),
                standingGroup(of: keptHere, at: station, now: now)
            ].compactMap { $0 }
        }
    }

    private static func key(of line: TransitLine) -> String {
        "\(line.mode)-\(line.name)"
    }

    private static func pairGroup(of kept: [Kept], lines: [TransitLine], at station: Station, now: Date) -> Group? {
        var paired: Set<Int> = []
        for line in lines {
            let ofTheLine = kept.indices.filter { key(of: kept[$0].departure.line) == key(of: line) }
            let departures = ofTheLine.map { kept[$0].departure }
            for row in LineDirections.trainsOfEachRow(of: line, at: station, from: departures) {
                let indices = keptIndices(of: row, among: ofTheLine, in: kept)
                for rank in row.indices.dropFirst()
                where row[rank].time.timeIntervalSince(row[rank - 1].time) < pairSpacing {
                    paired.formUnion([indices[rank - 1], indices[rank]].compactMap { $0 })
                }
            }
        }
        guard !paired.isEmpty else { return nil }
        return Group(
            .pair,
            at: station.name,
            lines: paired.sorted().flatMap { index in
                let departure = kept[index].departure
                let minutes = LineDirection.Train(time: departure.time, destination: departure.destination)
                    .countdownMinutes(at: now, on: departure.line.mode)
                return entryLines(of: kept[index].entry, adding: "shows \(minutes) min")
            }
        )
    }

    /// The entry of each train of a row: the rows hold the departures themselves, so two equal departures take
    /// their entries in order.
    private static func keptIndices(of row: [Departure], among candidates: [Int], in kept: [Kept]) -> [Int?] {
        var taken: Set<Int> = []
        return row.map { departure in
            guard let index = candidates.first(where: { !taken.contains($0) && kept[$0].departure == departure })
            else { return nil }
            taken.insert(index)
            return index
        }
    }

    private static func standingGroup(of kept: [Kept], at station: Station, now: Date) -> Group? {
        let standing = kept.filter { $0.departure.isAtStop && $0.departure.time <= now }
        guard !standing.isEmpty else { return nil }
        return Group(
            .standing,
            at: station.name,
            lines: standing.flatMap { item in
                let late = Int(now.timeIntervalSince(item.departure.time))
                return entryLines(of: item.entry, adding: "\(late) s past its time")
            }
        )
    }

    /// The lines of an entry, with a note at the end of its first line, which says what the app does with it.
    private static func entryLines(of entry: PRIMAnswerLog.Entry, adding note: String) -> [String] {
        guard let first = entry.lines.first else { return [] }
        return ["\(first) | \(note)"] + entry.lines.dropFirst()
    }
}
