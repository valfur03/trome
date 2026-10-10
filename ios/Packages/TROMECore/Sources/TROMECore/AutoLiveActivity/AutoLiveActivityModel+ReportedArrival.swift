import Foundation

extension AutoLiveActivityModel {
    /// iOS says that the phone entered the area of a station: the app decides on a position that it trusts
    /// (`ReportedArrivalRules`), and asks iOS for one when the last position does not settle it.
    func handleArrival(reportedAt station: Station, lastKnownFix: PositionFix?) async {
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
        guard let fix = WatchedRegion.recentFix(known, now: now) else { return }
        await handle(fix, maximumAge: maximumAge, logsEveryOutcome: true)
    }
}
