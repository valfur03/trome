public enum ArrivalNotificationAction: String, CaseIterable, Sendable {
    case notForOneHour = "stationArrival.snooze.oneHour"
    case notToday = "stationArrival.snooze.restOfToday"

    var snoozeDuration: SnoozeDuration {
        switch self {
        case .notForOneHour:
            .oneHour
        case .notToday:
            .restOfToday
        }
    }
}
