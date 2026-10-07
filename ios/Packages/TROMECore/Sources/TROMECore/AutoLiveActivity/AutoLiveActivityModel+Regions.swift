import Foundation

extension AutoLiveActivityModel {
    public func handleRegionEvent(enteredRegionId: String?, lastKnownFix: PositionFix?) async {
        guard inputs.locationService.source == .realGPS else {
            services.wakeLog?.record(.decision, "Ignored: a fake position is on")
            return
        }
        let fix = WatchedRegion.fix(
            afterEnteringRegionId: enteredRegionId,
            lastKnownFix: lastKnownFix,
            now: configuration.now(),
            catalog: catalog
        )
        guard let fix else {
            logNoRecentPosition(lastKnownFix)
            return
        }
        await handle(fix, maximumAge: AutoLiveActivityRules.maximumMonitoredPositionAge, logsEveryOutcome: true)
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
