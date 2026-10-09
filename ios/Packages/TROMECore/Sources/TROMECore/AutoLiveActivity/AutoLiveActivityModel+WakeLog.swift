import Foundation

extension AutoLiveActivityModel {
    func log(_ outcome: ArrivalOutcome?, everyOutcome: Bool) {
        guard let wakeLog = services.wakeLog, let outcome, everyOutcome || outcome.logKey != lastLoggedOutcomeKey else {
            return
        }
        lastLoggedOutcomeKey = outcome.logKey
        wakeLog.record(.decision, outcome.summary)
    }

    func logScreenChange(from oldPhase: AppPhase, to newPhase: AppPhase) {
        switch (oldPhase, newPhase) {
        case (.background, .active), (.background, .inactive):
            services.wakeLog?.record(.launch, "App on screen")
        case (.active, .background), (.inactive, .background):
            services.wakeLog?.record(.launch, "App in the background")
        default:
            break
        }
    }

    func logNoRecentPosition(_ lastKnownFix: PositionFix?) {
        guard let wakeLog = services.wakeLog else { return }
        guard let lastKnownFix else {
            wakeLog.record(.decision, "No decision: iOS gave no position")
            return
        }
        let age = Int(configuration.now().timeIntervalSince(lastKnownFix.timestamp))
        wakeLog.record(.decision, "No decision: the last position is \(age) s old")
    }

    func logPositionBeforeLeaving() {
        services.wakeLog?.record(.decision, "No decision: the last position is inside the area that the phone left")
    }

    func logUntrusted(_ fix: PositionFix, maximumAge: TimeInterval) {
        guard let wakeLog = services.wakeLog else { return }
        let age = Int(configuration.now().timeIntervalSince(fix.timestamp))
        wakeLog.record(.decision, """
            No decision: position not trusted, ±\(Int(fix.accuracyMeters)) m and \(age) s old \
            (needs ±\(Int(AutoLiveActivityRules.maximumAccuracyMeters)) m and \(Int(maximumAge)) s)
            """)
    }

    func logPlan(_ regions: [WatchedRegion], around position: Coordinate) {
        guard let wakeLog = services.wakeLog else { return }
        wakeLog.record(
            .regions, WatchedRegion.summary(of: regions, around: position, catalog: catalog), unlessRepeated: true
        )
    }
}
