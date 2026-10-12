import SwiftUI

extension Text {
    /// The whole minutes left until `end`, rounded down, as "4 minutes": it counts down by itself on the Live Activity,
    /// and holds "0 minutes" after `end`.
    ///
    /// A timer style and not `.offset`: `.offset` counts up again after its end, so a train that has left would read
    /// "1 minute", then "2 minutes", while the app is suspended and before iOS hides the waits.
    init(minutesLeftUntil end: Date) {
        self.init(.currentDate, format: Self.minutesLeft(until: end))
    }

    static func minutesLeft(until end: Date) -> SystemFormatStyle.Timer {
        .timer(countingDownIn: .distantPast..<end, showsHours: false, maxFieldCount: 1, maxPrecision: .seconds(60))
    }
}
