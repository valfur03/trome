#if DEBUG
import Foundation

public enum FakeTrainsScenario: String, Codable, CaseIterable, Sendable {
    case atPlatform = "at-platform"
    case atPlatformSecond = "at-platform-second"
    case atPlatformBoth = "at-platform-both"
    case tenToNine = "ten-to-nine"

    static let stopSeconds: TimeInterval = 30

    struct Train: Equatable {
        var index: Int
        var departureMinutes: Double
        var waitsAtThePlatformFromTheStart: Bool
    }

    private var firstTrains: [Train] {
        switch self {
        case .atPlatform:
            [waiting(leavesAt: 5), arriving(leavesAt: 8)]
        case .atPlatformSecond:
            [arriving(leavesAt: 5), waiting(leavesAt: 7)]
        case .atPlatformBoth:
            [waiting(leavesAt: 5), waiting(leavesAt: 7)]
        case .tenToNine:
            [arriving(leavesAt: 6), arriving(leavesAt: 12)]
        }
    }

    private var minutesBetweenTrains: Double {
        self == .tenToNine ? 6 : 4
    }

    func trains(leavingAfter minutes: Double, count: Int) -> [Train] {
        var timetable = firstTrains.enumerated().map { index, train in
            var train = train
            train.index = index
            return train
        }
        while timetable.filter({ $0.departureMinutes > minutes }).count < count, let last = timetable.last {
            timetable.append(Train(
                index: timetable.count,
                departureMinutes: last.departureMinutes + minutesBetweenTrains,
                waitsAtThePlatformFromTheStart: false
            ))
        }
        return Array(timetable.filter { $0.departureMinutes > minutes }.prefix(count))
    }

    private func waiting(leavesAt minutes: Double) -> Train {
        Train(index: 0, departureMinutes: minutes, waitsAtThePlatformFromTheStart: true)
    }

    private func arriving(leavesAt minutes: Double) -> Train {
        Train(index: 0, departureMinutes: minutes, waitsAtThePlatformFromTheStart: false)
    }
}
#endif
