import Foundation

extension AutoLiveActivityModel {
    /// The rider arrived at a station with the app in the background: with the silent start, the server starts the
    /// Live Activity. The app never notifies the arrival: a start that does not come leaves one line in the wake log,
    /// with its cause, and the rider who opens the app at the station gets the Live Activity then.
    /// The arrival rules give this once for each arrival, so a second event of iOS for the same station, even during
    /// the ask, asks nothing more.
    func startInTheBackground(at station: Station) async {
        guard let silentStart = services.silentStart else {
            recordNoStart(at: station, because: "the silent start is off in this build")
            return
        }
        guard liveActivity.areActivitiesEnabled else {
            recordNoStart(at: station, because: "Live Activities are off in Settings")
            return
        }
        // During the ask, the app opened at the station must not start a Live Activity of its own:
        // the one that Apple then brings would be a second.
        state.openArrivalStationId = nil
        followPositionInBackground()
        let ask = await silentStart.start(at: station)
        if state.arrivalStationId == station.id && state.shown == nil {
            state.openArrivalStationId = station.id
        }
        if ask.startsTheLiveActivity {
            followThePushedStart(at: station)
            return
        }
        endTheLocationKeptForTheAsk()
        recordNoStart(at: station, because: ask.cause)
    }

    /// The push may have landed during the ask: the app then follows it at once, and keeps the location as for a
    /// Live Activity that it started. Otherwise it follows it when iOS next runs the app: at the push, at a wake of
    /// a region, or when the rider opens it.
    private func followThePushedStart(at station: Station) {
        guard state.shown == nil else { return }
        state.pushedStart = PushedStart(stationId: station.id, answeredAt: configuration.now())
        syncWithSystem()
        if state.shown == nil {
            endTheLocationKeptForTheAsk()
        }
    }

    /// Follows the Live Activity that the push brought, as one that the app started; true when it does.
    @discardableResult
    func adoptThePushedLiveActivity() -> Bool {
        guard let adopted = configuration.rules.adoptThePushedLiveActivity(state: state) else { return false }
        state = adopted
        let name = shownStation?.name ?? adopted.shown?.stationId ?? ""
        services.wakeLog?.record(.silentStart, "Follows the Live Activity that the server started: \(name)")
        return true
    }

    /// The one line of a background start that does not come: it names the cause, and says that no banner stood in.
    private func recordNoStart(at station: Station, because cause: String) {
        services.wakeLog?.record(.silentStart, "No start at \(station.name), no notification: \(cause)")
    }

    /// iOS suspends a woken app seconds after the wake: the background location keeps it running for the ask.
    private func endTheLocationKeptForTheAsk() {
        guard secondChances.isEmpty, state.shown == nil || !liveActivity.isShowing else { return }
        stopFollowingPositionInBackground()
    }
}
