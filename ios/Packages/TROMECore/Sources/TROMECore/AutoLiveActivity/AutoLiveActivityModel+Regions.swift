import Foundation

extension AutoLiveActivityModel {
    public func handleRegionEvent(_ event: RegionEvent, lastKnownFix: PositionFix?) async {
        guard inputs.locationService.source == .realGPS else {
            services.wakeLog?.record(.decision, "Ignored: a fake position is on")
            return
        }
        endSecondChance(leaving: event)
        if let stationId = event.leftStopStationId {
            await apply(
                configuration.rules.leaveStopArea(of: stationId, state: state, catalog: catalog),
                logsEveryOutcome: true
            )
        }
        if let station = event.enteredRegionId.flatMap(WatchedRegion.arrivalStationId(inRegionId:))
            .flatMap(catalog.station(withId:)) {
            await handleArrival(reportedAt: station, lastKnownFix: lastKnownFix)
            return
        }
        guard let fix = WatchedRegion.recentFix(lastKnownFix, now: configuration.now()) else {
            logNoRecentPosition(lastKnownFix)
            return
        }
        if let stationId = event.leftStopStationId, isInsideStopArea(of: stationId, fix) {
            logPositionBeforeLeaving()
            return
        }
        await handle(fix, maximumAge: AutoLiveActivityRules.maximumMonitoredPositionAge, logsEveryOutcome: true)
    }

    /// A position inside the stop area that iOS says the phone left is older than the exit: deciding on it
    /// would take the rider back to the station, and notify a second time as they leave.
    private func isInsideStopArea(of stationId: String, _ fix: PositionFix) -> Bool {
        guard let station = catalog.station(withId: stationId) else { return false }
        return fix.coordinate.distance(to: station.coordinate) <= AutoLiveActivityRules.stopRadiusMeters
    }

    func refreshRegions(around position: Coordinate?) async {
        guard inputs.locationService.source == .realGPS else {
            guard plannedRegions != nil || !hasClearedRegions else { return }
            plannedRegions = nil
            hasClearedRegions = true
            services.wakeLog?.record(.regions, "No region watched: a fake position is on")
            await services.regionWatcher.watch([])
            return
        }
        guard let position else { return }
        hasClearedRegions = false
        let stopStationId = state.shown?.stationId ?? state.arrivalStationId
        if let plannedRegions, plannedRegions.stopStationId == stopStationId,
           plannedRegions.center.distance(to: position) < StationRegionPlan.replanDistanceMeters {
            return
        }
        plannedRegions = RegionPlanKey(center: position, stopStationId: stopStationId)
        let regions = StationRegionPlan.regions(
            around: position,
            stopStation: stopStationId.flatMap(catalog.station(withId:)),
            catalog: catalog
        )
        logPlan(regions, around: position)
        await services.regionWatcher.watch(regions)
    }
}
