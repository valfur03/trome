import Foundation

extension AutoLiveActivityModel {
    /// The rider arrived at a station with the app in the background: with the silent start, the server starts the
    /// Live Activity, and the arrival notification is only its fallback. The arrival rules give this once for each
    /// arrival, so a second event of iOS for the same station, even during the ask, asks nothing more.
    func announceArrival(at station: Station) async {
        guard let silentStart = services.silentStart else {
            await services.notifier.notify(station)
            return
        }
        guard liveActivity.areActivitiesEnabled else {
            await notifyAsTheFallback(at: station, because: "Live Activities are off in Settings")
            return
        }
        // During the ask, the app opened at the station must not start a Live Activity of its own:
        // the one that Apple then brings would be a second.
        state.openArrivalStationId = nil
        services.locationKeeper.begin()
        let isStarted = await silentStart.start(at: station)
        let isTheSameArrival = state.arrivalStationId == station.id && state.shown == nil
        if isTheSameArrival {
            state.openArrivalStationId = station.id
        }
        endTheLocationKeptForTheAsk()
        guard !isStarted else { return }
        guard isTheSameArrival, inputs.automaticMode.allowsAutomaticStart else {
            services.wakeLog?.record(.silentStart, "No fallback: the arrival at \(station.name) is over")
            return
        }
        await notifyAsTheFallback(at: station, because: nil)
    }

    private func notifyAsTheFallback(at station: Station, because reason: String?) async {
        let line = "Fallback: the arrival notification" + (reason.map { " (\($0))" } ?? "")
        services.wakeLog?.record(.silentStart, line)
        await services.notifier.notify(station)
    }

    /// iOS suspends a woken app seconds after the wake: the background location keeps it running for the ask.
    private func endTheLocationKeptForTheAsk() {
        guard secondChances.isEmpty, state.shown == nil || !liveActivity.isShowing else { return }
        services.locationKeeper.end()
    }
}
