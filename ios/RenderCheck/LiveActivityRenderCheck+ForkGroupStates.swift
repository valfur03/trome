import Foundation
import TROMECore

extension LiveActivityRenderCheck {
    static let forkStatesStation = "Liège"
    static let firstForkStatesPage = 95
    static let forkStatesHub = "Place de Clichy"

    static func forkGroupStates(
        at station: Station,
        hub: Station,
        now: Date
    ) -> [StationActivityAttributes.ContentState] {
        guard let line = station.lines.first, let ends = line.ends else { return [] }
        let pages = ForkGroupPages(now: now, northEnds: ends.first, south: ends.second[0])
        let everyState = pages.everyState
        let atPlatform = pages.atPlatform
        let longName = "\(station.name) - Aubervilliers - Pantin - Quatre Chemins - Fort d'Aubervilliers"
        let longNamePages = [everyState[0], [everyState[0][0]], [], atPlatform[0]]
        let hubPages = [atPlatform[0], atPlatform[2]]
        let drawn = (everyState + atPlatform).map { (station.name, [line], $0, now) }
            + longNamePages.map { (longName, [line], $0, now) }
            + hubPages.map { (hub.name, hub.lines, $0, now) }
            + [(station.name, [line], pages.countedDownBelowTen, now.addingTimeInterval(-90))]
        + [(station.name, [line], pages.oneEndOverAnHourOnly, now)]
        return drawn.map { name, allLines, directions, updatedAt in
            StationActivityAttributes.ContentState(
                stationName: name,
                trains: .lines(LinesPage(
                    lines: [LineTrains(line: line, directions: directions, hasADirectionWithTwoEnds: true)],
                    allLines: allLines,
                    firstIndex: 0,
                    soonestTrain: nil
                )),
                updatedAt: updatedAt
            )
        }
    }
}

private struct ForkGroupPages {
    let now: Date
    let northEnds: [String]
    let south: String

    var everyState: [[LineDirection]] {
        [
            [
                north(first: [train(0.75, .approaching), train(6)], second: [train(0.5, .atPlatform), train(9)]),
                southward([train(12), train(59.5)])
            ],
            [north(first: [], firstOverAnHour: true, second: [train(2.5)]), southward([], overAnHour: true)],
            [north(first: [train(3), train(9)], second: []), southward([])],
            [north(first: [], second: []), southward([train(4), train(8)])],
            [
                north(first: [], firstOverAnHour: true, second: [], secondOverAnHour: true, overAnHour: true),
                southward([train(4)])
            ],
            [
                north(first: [], second: [train(7)], shortTrip: train(3, to: "Porte de Saint-Ouen")),
                southward([train(4)])
            ]
        ]
    }

    var atPlatform: [[LineDirection]] {
        [
            [
                north(first: [train(14.5), train(21)], second: [train(0.4, .atPlatform), train(12)]),
                southward([train(3.5), train(12.5)])
            ],
            [
                north(first: [train(0.2, .atPlatform), train(0.6, .atPlatform)], second: [train(10.5), train(16)]),
                southward([train(0.3, .atPlatform), train(12.5)])
            ],
            [
                north(
                    first: [train(0.2, .atPlatform), train(4)],
                    second: [train(0.5, .atPlatform), train(0.9, .atPlatform)]
                ),
                southward([train(4.5), train(59.5)])
            ]
        ]
    }

    var countedDownBelowTen: [LineDirection] {
        [
            north(first: [train(4), train(8.5)], second: [train(6), train(8.5)]),
            southward([train(3), train(7)])
        ]
    }

    var oneEndOverAnHourOnly: [LineDirection] {
        [
            north(first: [], firstOverAnHour: true, second: [], overAnHour: true),
            southward([train(4), train(8)])
        ]
    }

    private func train(_ minutes: Double, _ status: PlatformStatus? = nil, to end: String = "") -> LineDirection.Train {
        LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: end, status: status)
    }

    private func north(
        first: [LineDirection.Train],
        firstOverAnHour: Bool = false,
        second: [LineDirection.Train],
        secondOverAnHour: Bool = false,
        overAnHour: Bool = false,
        shortTrip: LineDirection.Train? = nil
    ) -> LineDirection {
        let rows = [(first, firstOverAnHour), (second, secondOverAnHour)].enumerated().map { index, row in
            BranchEndTrains(end: northEnds[index], trains: row.0.to(northEnds[index]), nextTrainIsOverAnHourAway: row.1)
        }
        let trains = (rows.flatMap(\.trains) + [shortTrip].compactMap { $0 }).sorted { $0.time < $1.time }
        return LineDirection(
            label: northEnds.joined(separator: " / "),
            trains: Array(trains.prefix(2)),
            nextTrainIsOverAnHourAway: overAnHour,
            branchEnds: northEnds,
            trainsOfEachEnd: rows
        )
    }

    private func southward(_ trains: [LineDirection.Train], overAnHour: Bool = false) -> LineDirection {
        LineDirection(label: south, trains: trains.to(south), nextTrainIsOverAnHourAway: overAnHour)
    }
}

private extension [LineDirection.Train] {
    func to(_ end: String) -> [LineDirection.Train] {
        map { LineDirection.Train(time: $0.time, destination: end, status: $0.status) }
    }
}
