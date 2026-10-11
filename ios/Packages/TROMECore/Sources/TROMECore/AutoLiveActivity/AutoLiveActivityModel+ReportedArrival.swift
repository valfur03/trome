import Foundation

extension AutoLiveActivityModel {
    /// iOS says that the phone entered the area of a station: the app decides on a position that it trusts
    /// (`ReportedArrivalRules`), and asks iOS for one when the last position does not settle it.
    /// With no trusted position at all, the refusal is not final: the report gets a second chance.
    func handleArrival(reportedAt station: Station, lastKnownFix: PositionFix?) async {
        let reportedAt = configuration.now()
        var known = lastKnownFix
        if ReportedArrivalRules.position(confirming: station, with: known, now: configuration.now()) == nil,
           !ReportedArrivalRules.settles(known, now: configuration.now()) {
            known = await freshPosition(waitingAtMost: ReportedArrivalRules.maximumWait) ?? known
        }
        let now = configuration.now()
        let maximumAge = AutoLiveActivityRules.maximumMonitoredPositionAge
        if let fix = ReportedArrivalRules.position(confirming: station, with: known, now: now) {
            await handle(fix, maximumAge: maximumAge, logsEveryOutcome: true)
            return
        }
        services.wakeLog?.record(.decision, ReportedArrivalRules.refusal(at: station, position: known, now: now))
        if let fix = WatchedRegion.recentFix(known, now: now) {
            await handle(fix, maximumAge: maximumAge, logsEveryOutcome: true)
        }
        if !ReportedArrivalRules.isFinal(refusalWith: known, now: now) {
            giveASecondChance(to: station, reportedAt: reportedAt)
        }
    }
}
