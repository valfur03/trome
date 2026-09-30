import Foundation
import RATPCore

extension LiveActivityRenderCheck {
    static let stripStatesStation = "Lamarck - Caulaincourt"
    static let firstStripStatesPage = 90

    static func stripStates(at station: Station, now: Date) -> [StationActivityAttributes.ContentState] {
        guard let line = station.lines.first else { return [] }
        func train(_ minutes: Double, _ status: PlatformStatus? = nil) -> LineDirection.Train {
            LineDirection.Train(time: now.addingTimeInterval(minutes * 60), destination: "", status: status)
        }
        func direction(_ end: String, _ trains: [LineDirection.Train], overAnHour: Bool = false) -> LineDirection {
            LineDirection(
                label: end,
                trains: trains.map { LineDirection.Train(time: $0.time, destination: end, status: $0.status) },
                nextTrainIsOverAnHourAway: overAnHour
            )
        }
        let north = "Mairie d'Aubervilliers"
        let south = "Mairie d'Issy"
        let pages = [
            [
                direction(north, [train(0.75, .approaching), train(7)]),
                direction(south, [train(0.5, .atPlatform), train(5)])
            ],
            [direction(north, [train(2.5)]), direction(south, [train(12), train(59.5)])],
            [direction(north, [], overAnHour: true), direction(south, [])],
            [direction(south, [train(3), train(7)])],
            [
                direction(north, [train(59.5), train(59.9)]),
                direction(south, [train(0.5, .atPlatform), train(0.75, .approaching)])
            ]
        ]
        return pages.map { directions in
            StationActivityAttributes.ContentState(
                stationName: station.name,
                trains: .lines(LinesPage(
                    lines: [LineTrains(line: line, directions: directions)],
                    allLines: [line],
                    firstIndex: 0,
                    soonestTrain: nil
                )),
                updatedAt: now
            )
        }
    }
}
