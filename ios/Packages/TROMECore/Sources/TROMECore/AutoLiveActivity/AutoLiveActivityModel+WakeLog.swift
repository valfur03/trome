import Foundation

extension AutoLiveActivityModel {
    func log(_ outcome: ArrivalOutcome?, everyOutcome: Bool, from origin: PositionOrigin? = nil) {
        guard let wakeLog = services.wakeLog, let outcome, everyOutcome || outcome.logKey != lastLoggedOutcomeKey else {
            return
        }
        lastLoggedOutcomeKey = outcome.logKey
        let summary = services.silentStart == nil ? outcome.summary : outcome.summaryWithASilentStart
        guard case .switched = outcome else {
            wakeLog.record(.decision, summary)
            return
        }
        wakeLog.record(.decision, summary + Self.suffix(for: origin))
    }

    func log(_ ending: LiveActivityEnding?, from origin: PositionOrigin? = nil) {
        guard let ending else { return }
        guard case .farFrom = ending else {
            services.wakeLog?.record(.decision, ending.summary)
            return
        }
        services.wakeLog?.record(.decision, ending.summary + Self.suffix(for: origin))
    }

    /// A switch or an end on a position of the real GPS says where the position came from: on a walk, a Live Activity
    /// that moves only on the keeper's positions shows that iOS stopped the stream in the background.
    private static func suffix(for origin: PositionOrigin?) -> String {
        guard let origin else { return "" }
        return " (position: \(origin.rawValue))"
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

    /// An exit with no recent position decides nothing and plans no new areas: a walk reads from it why the stations
    /// further on may not be watched.
    func logNoRecentPosition(_ lastKnownFix: PositionFix?) {
        guard let wakeLog = services.wakeLog else { return }
        guard let lastKnownFix else {
            wakeLog.record(.decision, "No decision and no new areas: iOS gave no position")
            return
        }
        let age = Int(configuration.now().timeIntervalSince(lastKnownFix.timestamp))
        wakeLog.record(.decision, "No decision and no new areas: the last position is \(age) s old")
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

    func logBackgroundCall(at station: Station, nextCall: Date?) {
        guard let wakeLog = services.wakeLog, !Task.isCancelled, shownStation?.id == station.id else { return }
        wakeLog.record(.trains, BackgroundTrainsLogLine.text(
            station: station,
            state: inputs.liveActivityTrains.state(for: station),
            now: configuration.now(),
            nextCall: nextCall
        ))
    }
}
