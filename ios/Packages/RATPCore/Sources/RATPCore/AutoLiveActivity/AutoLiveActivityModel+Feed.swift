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
        var waits = !fetchNow
        while !Task.isCancelled {
            if waits {
                let staleDate = liveActivity.content?.staleDate
                let delay = asksPRIM
                    ? BackgroundTrainsRefresh.delay(untilStale: staleDate, now: configuration.now())
                    : BackgroundTrainsRefresh.maximumDelay
                do {
                    try await configuration.sleep(.seconds(delay))
                } catch {
                    return
                }
            }
            waits = true
            syncWithSystem()
            guard liveActivity.isShowing else { return }
            guard asksPRIM else { continue }
            await feed(station)
            asksPRIM = BackgroundTrainsRefresh.shouldAskAgain(after: inputs.liveActivityTrains.state(for: station))
        }
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
