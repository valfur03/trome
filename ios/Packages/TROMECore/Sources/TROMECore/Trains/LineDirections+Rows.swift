import Foundation

extension LineDirections {
    static func directions(
        of line: TransitLine,
        at station: Station,
        trainsFrom departures: [Departure],
        now: Date,
        showsEverySide: Bool = false
    ) -> [LineDirection] {
        rows(of: line, at: station, trainsFrom: departures, showsEverySide: showsEverySide).map { row in
            switch row {
            case .side(let side, let trains):
                direction(of: line, toward: side, from: station, trains: trains, now: now)
            case .other(let trains):
                LineDirection(
                    label: trains[0].destination,
                    trains: withStatuses(trains, of: line, at: now).prefix(timesPerDirection).map { shown($0) }
                )
            }
        }
    }

    /// The trains of each row that the screen shows for a line, one entry per train, in time order, before the
    /// rows keep their first times: the walk record reads them to find two entries of one side under 60 s apart.
    static func trainsOfEachRow(
        of line: TransitLine,
        at station: Station,
        from departures: [Departure]
    ) -> [[Departure]] {
        rows(of: line, at: station, trainsFrom: departures, showsEverySide: false).map { row in
            switch row {
            case .side(_, let trains), .other(let trains): trains
            }
        }
    }

    /// A row of a line on the screen: the trains toward one side, or those of a quay or a destination with no side.
    enum Row {
        case side([String], [Departure])
        case other([Departure])
    }
}
