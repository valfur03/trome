import Foundation
import RATPCore

extension LiveActivityRenderCheck {
    static let taggedStatesStation = "Liège"
    static let firstTaggedStatesPage = 95
    static let taggedStatesHub = "Place de Clichy"

    static func taggedStripStates(
        at station: Station,
        hub: Station,
        now: Date
    ) -> [StationActivityAttributes.ContentState] {
        guard let line = station.lines.first, let ends = line.ends else { return [] }
        let pages = TaggedStripPages(now: now, northEnds: ends.first, south: ends.second[0])
        let everyState = pages.everyState
        let atPlatform = pages.atPlatform
        let longName = "\(station.name) - Aubervilliers - Pantin - Quatre Chemins - Fort d'Aubervilliers"
        let longNamePages = [everyState[0], [everyState[0][0]], [], atPlatform[0]]
        let hubPages = [atPlatform[0], atPlatform[2]]
        let drawn = (everyState + atPlatform).map { (station.name, [line], $0) }
            + longNamePages.map { (longName, [line], $0) }
            + hubPages.map { (hub.name, hub.lines, $0) }
        return drawn.map { name, allLines, directions in
            StationActivityAttributes.ContentState(
                stationName: name,
                trains: .lines(LinesPage(
                    lines: [LineTrains(line: line, directions: directions, hasADirectionWithTwoEnds: true)],
                    allLines: allLines,
                    firstIndex: 0,
                    soonestTrain: nil
                )),
                updatedAt: now
            )
        }
    }
}

private struct TaggedStripPages {
    let now: Date
    let northEnds: [String]
    let south: String

    var everyState: [[LineDirection]] {
        [
            [
                north([train(0.75, northEnds[0], .approaching), train(0.5, northEnds[1], .atPlatform)]),
                southward([train(12, south), train(59.5, south)])
            ],
            [north([train(2.5, northEnds[1])]), southward([], overAnHour: true)],
            [north([train(3, northEnds[0]), train(9, northEnds[0])]), southward([])],
            [north([]), southward([train(4, south), train(8, south)])],
            [north([], overAnHour: true), southward([train(4, south)])],
            [north([train(3, "Porte de Saint-Ouen"), train(7, northEnds[1])]), southward([train(4, south)])]
        ]
    }

    var atPlatform: [[LineDirection]] {
        [
            [
                north([train(0.4, northEnds[1], .atPlatform), train(14.5, northEnds[0])]),
                southward([train(3.5, south), train(12.5, south)])
            ],
            [
                north([train(10.5, northEnds[0]), train(0.4, northEnds[1], .atPlatform)]),
                southward([train(0.3, south, .atPlatform), train(12.5, south)])
            ],
            [
                north([train(0.2, northEnds[0], .atPlatform), train(0.5, northEnds[1], .atPlatform)]),
                southward([train(4.5, south), train(59.5, south)])
            ]
        ]
    }

    private func train(_ minutes: Double, _ end: String, _ status: PlatformStatus? = nil) -> LineDirection.Train {
        LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: end, status: status)
    }

    private func north(_ trains: [LineDirection.Train], overAnHour: Bool = false) -> LineDirection {
        LineDirection(
            label: northEnds.joined(separator: " / "),
            trains: trains,
            nextTrainIsOverAnHourAway: overAnHour,
            branchEnds: northEnds
        )
    }

    private func southward(_ trains: [LineDirection.Train], overAnHour: Bool = false) -> LineDirection {
        LineDirection(label: south, trains: trains, nextTrainIsOverAnHourAway: overAnHour)
    }
}
