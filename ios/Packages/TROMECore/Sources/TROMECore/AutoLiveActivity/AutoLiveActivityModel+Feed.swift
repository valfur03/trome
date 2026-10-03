import Foundation

extension AutoLiveActivityModel {
    func startFeedAfterLaunch() {
        guard let station = shownStation, liveActivity.isShowing else { return }
        feedTask = Task { [weak self, sleep = configuration.sleep] in
            do {
                try await sleep(.seconds(BackgroundTrainsRefresh.launchDelay))
            } catch {
                return
            }
            await self?.keepFeedingInBackground(station, fetchNow: true)
        }
    }

    func feedAfterActivityChange(wasActive: Bool) {
        guard !appIsActive else {
            feedTask?.cancel()
            feedTask = nil
            return
        }
        if wasActive || feedTask == nil {
            restartFeed(fetchNow: false)
        }
    }

    func restartFeed(fetchNow: Bool) {
        feedTask?.cancel()
        feedTask = nil
        guard let station = shownStation, liveActivity.isShowing else { return }
        if appIsActive {
            guard inputs.screenTrains.updatingStationId != station.id else { return }
            feedTask = Task { [weak self] in
                await self?.keepFeeding(station)
            }
        } else {
            feedTask = Task { [weak self] in
                await self?.keepFeedingInBackground(station, fetchNow: fetchNow)
            }
        }
    }

    func keepFeedingInBackground(_ station: Station, fetchNow: Bool) async {
        var asksPRIM = true
        var nextCall = fetchNow || waitsForItsTrains ? configuration.now() : nextPRIMCall(asksPRIM: asksPRIM)
        while !Task.isCancelled {
            let now = configuration.now()
            let redrawDate = liveActivity.nextRedrawDate(after: now)
                .flatMap { $0 < nextCall ? $0 : nil }
            let delay = (redrawDate ?? nextCall).timeIntervalSince(now)
            if delay > 0 {
                do {
                    try await configuration.sleep(.seconds(delay.rounded(.up)))
                } catch {
                    return
                }
            }
            syncWithSystem()
            guard liveActivity.isShowing else { return }
            if redrawDate != nil {
                await liveActivity.redraw()
                continue
            }
            if asksPRIM {
                await feed(station)
                asksPRIM = BackgroundTrainsRefresh.shouldAskAgain(after: inputs.liveActivityTrains.state(for: station))
            }
            nextCall = nextPRIMCall(asksPRIM: asksPRIM)
        }
    }

    private var waitsForItsTrains: Bool {
        liveActivity.content?.trains == .loading
    }

    private func nextPRIMCall(asksPRIM: Bool) -> Date {
        let now = configuration.now()
        let delay = asksPRIM
            ? BackgroundTrainsRefresh.delay(untilStale: liveActivity.content?.staleDate, now: now)
            : BackgroundTrainsRefresh.maximumDelay
        return now.addingTimeInterval(delay)
    }

    func keepFeeding(_ station: Station) async {
        while !Task.isCancelled {
            await feed(station)
            do {
                try await configuration.sleep(NextTrainsModel.refreshInterval)
            } catch {
                return
            }
        }
    }

    func feed(_ station: Station) async {
        let trains = inputs.liveActivityTrains
        await trains.refresh(for: station)
        guard !Task.isCancelled, shownStation?.id == station.id else { return }
        await liveActivity.update(station: station, trains: trains.state(for: station))
    }
}
