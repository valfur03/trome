import Foundation

extension AutoLiveActivityModel {
    /// The test of the start, from the record of a build for a walk: the rider at a desk asks the server to start the
    /// Live Activity of the nearest station of the list, whatever its distance, through the same ask, the same lines
    /// and the same follow-up as a wake at a station. So the ask, Apple's push and the show are seen in a minute,
    /// before a walk. Its Live Activity ends as one started by hand: by distance once the phone has been within
    /// 250 meters of the station, and 45 minutes after the server's answer.
    /// It asks nothing with no position, or while a Live Activity shows, as a wake would not ask then either; it
    /// ignores the automatic mode and the pause, which a test is not about. Returns whether the ask left.
    @discardableResult
    public func testTheStart() -> Bool {
        guard let position = inputs.locationService.position,
              let nearest = catalog.nearestStation(to: position, within: .infinity) else {
            services.wakeLog?.record(.decision, "Test of the start: no position, nothing asked")
            return false
        }
        guard state.shown == nil, !liveActivity.isShowing else {
            services.wakeLog?.record(.decision, "Test of the start: a Live Activity shows, nothing asked")
            return false
        }
        let station = nearest.station
        services.wakeLog?.record(
            .decision, "Test of the start by the rider: \(station.name), \(Int(nearest.distanceMeters)) m away"
        )
        let hasBeenNear = precisePosition().map {
            $0.distance(to: station.coordinate) <= AutoLiveActivityRules.stopRadiusMeters
        } ?? false
        startTestTask = Task { [weak self] in
            await self?.startInTheBackground(at: station, hasBeenNear: hasBeenNear)
        }
        return services.silentStart != nil && liveActivity.areActivitiesEnabled
    }
}
