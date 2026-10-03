import Testing
@testable import TROMECore

struct ArrivalNotificationActionTests {
    @Test(arguments: [
        (ArrivalNotificationAction.notForOneHour, SnoozeDuration.oneHour),
        (.notToday, .restOfToday)
    ])
    func snoozesForTheDurationOfTheAction(action: ArrivalNotificationAction, duration: SnoozeDuration) {
        #expect(action.snoozeDuration == duration)
    }

    @Test func findsEachActionFromItsIdentifierOnly() {
        #expect(ArrivalNotificationAction(rawValue: "stationArrival.snooze.oneHour") == .notForOneHour)
        #expect(ArrivalNotificationAction(rawValue: "stationArrival.snooze.restOfToday") == .notToday)
        #expect(ArrivalNotificationAction(rawValue: "com.apple.UNNotificationDefaultActionIdentifier") == nil)
        #expect(ArrivalNotificationAction(rawValue: "com.apple.UNNotificationDismissActionIdentifier") == nil)
    }
}
