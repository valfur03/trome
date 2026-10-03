import Foundation

enum ResumePositionRules {
    static let maximumWait: Duration = .seconds(5)
    static let maximumFallbackAge = AutoLiveActivityRules.maximumMonitoredPositionAge

    static func usesWithoutWaiting(_ held: PositionFix?, now: Date) -> Bool {
        held.map { AutoLiveActivityRules.trusts($0, now: now) } ?? false
    }

    static func position(fresh: PositionFix?, held: PositionFix?, now: Date) -> PositionFix? {
        [fresh, held].lazy.compactMap { $0 }.first {
            AutoLiveActivityRules.trusts($0, now: now, maximumAge: maximumFallbackAge)
        }
    }
}
