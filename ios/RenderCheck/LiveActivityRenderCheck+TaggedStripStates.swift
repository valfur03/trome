import Foundation
import RATPCore

extension LiveActivityRenderCheck {
    static let taggedStatesStation = "Liège"
    static let firstTaggedStatesPage = 95

    static func taggedStripStates(at station: Station, now: Date) -> [StationActivityAttributes.ContentState] {
        guard let line = station.lines.first, let ends = line.ends else { return [] }
        let northEnds = ends.first
        let south = ends.second[0]
        func train(_ minutes: Double, _ end: String, _ status: PlatformStatus? = nil) -> LineDirection.Train {
            LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: end, status: status)
        }
        func north(_ trains: [LineDirection.Train], overAnHour: Bool = false) -> LineDirection {
            LineDirection(
                label: northEnds.joined(separator: " / "),
                trains: trains,
                nextTrainIsOverAnHourAway: overAnHour,
                branchEnds: northEnds
            )
        }
        func southward(_ trains: [LineDirection.Train], overAnHour: Bool = false) -> LineDirection {
            LineDirection(label: south, trains: trains, nextTrainIsOverAnHourAway: overAnHour)
        }
        let pages = [
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
        let longName = "\(station.name) - Aubervilliers - Pantin - Quatre Chemins - Fort d'Aubervilliers"
        let longNamePages = [pages[0], [pages[0][0]], []]
        let names = Array(repeating: station.name, count: pages.count)
            + Array(repeating: longName, count: longNamePages.count)
        return zip(names, pages + longNamePages).map { name, directions in
            StationActivityAttributes.ContentState(
                stationName: name,
                trains: .lines(LinesPage(
                    lines: [LineTrains(line: line, directions: directions, hasADirectionWithTwoEnds: true)],
                    allLines: [line],
                    firstIndex: 0,
                    soonestTrain: nil
                )),
                updatedAt: now
            )
        }
    }
}
