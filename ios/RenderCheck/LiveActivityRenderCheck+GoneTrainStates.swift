import Foundation
import TROMECore
import XCTest

extension LiveActivityRenderCheck {
    static let firstGoneTrainStatesPage = 150
    static let secondsAfterTheGoneTrain: [TimeInterval] = [0, 30, 60, 120]

    /// A metro train that has left while the app is suspended: the last content came 90 s before its time, so the app
    /// drew no approach and no departure, and the wait counts by itself. One page for each moment after the train time,
    /// drawn as iOS draws it until it applies the stale date (it can be 30 to 45 s late).
    static func goneTrainState(
        at station: Station,
        secondsAfterTheTrain: TimeInterval,
        now: Date
    ) -> StationActivityAttributes.ContentState? {
        guard let line = station.lines.first else { return nil }
        let trainTime = now.addingTimeInterval(-secondsAfterTheTrain)
        func direction(_ end: String, nextInMinutes: Double) -> LineDirection {
            LineDirection(label: end, trains: [
                LineDirection.Train(time: trainTime, destination: end),
                LineDirection.Train(time: trainTime.addingTimeInterval(nextInMinutes * 60), destination: end)
            ])
        }
        return StationActivityAttributes.ContentState(
            stationName: station.name,
            trains: .lines(LinesPage(
                lines: [LineTrains(line: line, directions: [
                    direction("Mairie d'Aubervilliers", nextInMinutes: 4),
                    direction("Mairie d'Issy", nextInMinutes: 7)
                ])],
                allLines: [line],
                firstIndex: 0,
                soonestTrain: nil
            )),
            updatedAt: trainTime.addingTimeInterval(-90)
        )
    }

    func drawTheGoneTrainStates(at station: Station, into outDir: URL) throws -> [String] {
        var rows: [String] = []
        for (page, seconds) in Self.secondsAfterTheGoneTrain.enumerated() {
            let state = try XCTUnwrap(Self.goneTrainState(at: station, secondsAfterTheTrain: seconds, now: Date()))
            let pageNumber = Self.firstGoneTrainStatesPage + page
            rows += try drawEveryVariant(of: state, at: station, page: pageNumber, into: outDir)
        }
        return rows
    }
}
