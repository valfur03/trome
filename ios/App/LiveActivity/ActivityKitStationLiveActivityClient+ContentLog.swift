#if DEBUG
import Foundation
import os
import TROMECore

extension ActivityKitStationLiveActivityClient {
    nonisolated private static let contentLogger = Logger(category: "LiveActivityContent")
    nonisolated private static let timeStyle = Date.ISO8601FormatStyle(timeZone: .current)
        .time(includingFractionalSeconds: false)

    nonisolated static func log(_ content: StationActivityAttributes.ContentState, sentBy call: String) {
        let updatedAt = content.updatedAt.formatted(timeStyle)
        let message = "\(call) \(content.stationName) at \(updatedAt): \(describe(content.trains))"
        contentLogger.notice("\(message, privacy: .public)")
    }

    nonisolated private static func describe(_ trains: StationActivityAttributes.Trains) -> String {
        switch trains {
        case .loading:
            return "loading"
        case .noData:
            return "no data"
        case .lines(let page):
            let lines = page.lines.map { line in
                let directions = line.directions.map { direction in
                    let shown = direction.trains.map(describe).joined(separator: ", ")
                    let later = direction.nextTrainIsOverAnHourAway ? " (over 1 h)" : ""
                    return "\(direction.label): \(shown.isEmpty ? "none" : shown)\(later)\(describeRows(of: direction))"
                }
                return "\(line.line.mode.rawValue) \(line.line.name) [\(directions.joined(separator: " | "))]"
            }
            return "page from \(page.firstIndex): " + lines.joined(separator: " ")
        }
    }

    nonisolated private static func describeRows(of direction: LineDirection) -> String {
        guard let rows = direction.trainsOfEachEnd else { return "" }
        let described = rows.map { row in
            let shown = row.trains.map(describe).joined(separator: ", ")
            let later = row.nextTrainIsOverAnHourAway ? " (over 1 h)" : ""
            return "\(row.end) = \(shown.isEmpty ? "none" : shown)\(later)"
        }
        return "; rows: " + described.joined(separator: "; ")
    }

    nonisolated private static func describe(_ train: LineDirection.Train) -> String {
        let status = train.status.map { " \($0.rawValue)" } ?? ""
        return "\(train.time.formatted(timeStyle)) \(train.destination)\(status)"
    }
}
#endif
