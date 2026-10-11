#if DEBUG
import Foundation

enum FakeTrainsScenario: String, Codable, CaseIterable, Sendable {
    case atPlatform = "at-platform"
    case atPlatformSecond = "at-platform-second"
    case atPlatformBoth = "at-platform-both"
    case tenToNine = "ten-to-nine"
    case forkEndWithOneTrain = "fork-end-one-train"
    case forkEndWithNoTrain = "fork-end-no-train"
    case forkEndOverAnHour = "fork-end-over-an-hour"
    case serverOut = "server-out"
    case serverOutUntilTomorrow = "server-out-tomorrow"
    case appTokenRefused = "app-token-refused"

    static let stopSeconds: TimeInterval = 30
    static let laterTrainMinutes: Double = 70
    static let serverOutMinutes: ClosedRange<Double> = 1...8
    static let serverRetrySecond: TimeInterval = 40
    static let appTokenRefusedAfter: TimeInterval = 60

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
        case .forkEndWithOneTrain, .forkEndWithNoTrain, .forkEndOverAnHour:
            [arriving(leavesAt: 4), arriving(leavesAt: 8)]
        case .serverOut, .serverOutUntilTomorrow, .appTokenRefused:
            [arriving(leavesAt: 3), arriving(leavesAt: 7)]
        }
    }

    private var minutesBetweenTrains: Double {
        self == .tenToNine ? 6 : 4
    }

    func endIndex(of train: Train, amongEnds count: Int) -> Int {
        guard count > 1 else { return 0 }
        switch self {
        case .forkEndWithOneTrain:
            return train.index == 1 ? 1 : 0
        case .forkEndWithNoTrain, .forkEndOverAnHour:
            return 0
        case .atPlatform, .atPlatformSecond, .atPlatformBoth, .tenToNine, .serverOut, .serverOutUntilTomorrow,
             .appTokenRefused:
            return train.index % count
        }
    }

    func serverRetryAt(from start: Date, now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .serverOut:
            let minutes = now.timeIntervalSince(start) / 60
            guard minutes >= Self.serverOutMinutes.lowerBound, minutes < Self.serverOutMinutes.upperBound else {
                return nil
            }
            return start.addingTimeInterval(Self.serverOutMinutes.upperBound * 60)
        case .serverOutUntilTomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start
            let retryAt = tomorrow.addingTimeInterval(Self.serverRetrySecond)
            return now < retryAt ? retryAt : nil
        case .atPlatform, .atPlatformSecond, .atPlatformBoth, .tenToNine, .forkEndWithOneTrain, .forkEndWithNoTrain,
             .forkEndOverAnHour, .appTokenRefused:
            return nil
        }
    }

    /// Whether the fake server refuses the app token: from 1 minute after the launch, as after a change of the
    /// token on the server, so that the Live Activity first shows times.
    func refusesTheAppToken(from start: Date, now: Date) -> Bool {
        self == .appTokenRefused && now.timeIntervalSince(start) >= Self.appTokenRefusedAfter
    }

    func laterTrainEndIndex(amongEnds count: Int) -> Int? {
        self == .forkEndOverAnHour && count > 1 ? 1 : nil
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
