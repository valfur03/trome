import Foundation

extension AutoLiveActivityModel {
    /// A reason why nothing started is written once while it stays the same; an outcome that acts is written each
    /// time, or a start again at the station of the last start line would leave its end line with no start before it.
    func log(_ outcome: ArrivalOutcome?, everyOutcome: Bool, from origin: PositionOrigin? = nil) {
        guard let wakeLog = services.wakeLog, let outcome,
              everyOutcome || outcome.acts || outcome.logKey != lastLoggedOutcomeKey else {
            return
        }
        lastLoggedOutcomeKey = outcome.logKey
        guard case .switched = outcome else {
            wakeLog.record(.decision, outcome.summary)
            return
        }
        wakeLog.record(.decision, outcome.summary + suffix(for: origin))
    }

    func log(_ ending: LiveActivityEnding?, from origin: PositionOrigin? = nil) {
        guard let ending else { return }
        guard case .farFrom = ending else {
            services.wakeLog?.record(.decision, ending.summary)
            return
        }
        services.wakeLog?.record(.decision, ending.summary + suffix(for: origin))
    }

    /// A switch or an end on a position of the real GPS says where the position came from, and, for the keeper,
    /// how old the last position of the stream was: on a walk, a stream minutes old while the rider moves shows that
    /// iOS stopped it in the background; a stream a few seconds old shows that it still ran.
    private func suffix(for origin: PositionOrigin?) -> String {
        switch origin {
        case nil:
            ""
        case .stream:
            " (position: stream)"
        case .keeper(let lastStreamFix?):
            " (position: keeper; stream \(Int(configuration.now().timeIntervalSince(lastStreamFix))) s old)"
        case .keeper(nil):
            " (position: keeper; no stream position)"
        }
    }

    /// A start by hand is no decision of the rules, but the record needs its line, or its end line has no start.
    func logStartByHand(at station: Station) {
        services.wakeLog?.record(.decision, "Live Activity started by hand: \(station.name)")
    }

    func logScreenChange(from oldPhase: AppPhase, to newPhase: AppPhase) {
        switch (oldPhase, newPhase) {
        case (.background, .active), (.background, .inactive):
            services.wakeLog?.recordScreenOnFront()
        case (.active, .background), (.inactive, .background):
            services.wakeLog?.record(.launch, "App in the background")
            logRegionHoldLater()
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

    /// The line of `RegionHoldLine`, after what iOS holds is read: the area of the station nearest the last position.
    /// None with a fake position, as the app then watches no area.
    func logRegionHoldLater() {
        guard let wakeLog = services.wakeLog, inputs.locationService.source == .realGPS else { return }
        let keptAwake = isKeepingAwake
        Task { [weak self, regionWatcher = services.regionWatcher] in
            let holds = await regionWatcher.holds()
            guard let self else { return }
            let text = RegionHoldLine.text(
                holds: holds,
                near: inputs.locationService.fix?.coordinate ?? plannedRegions?.center,
                keptAwake: keptAwake,
                now: configuration.now(),
                catalog: catalog
            )
            guard wakeLog.entries.first(where: RegionHoldLine.isHoldLine)?.text != text else { return }
            wakeLog.record(.system, text, keepingAtMost: RegionHoldLine.maximumLines, alike: RegionHoldLine.isHoldLine)
        }
    }
}
