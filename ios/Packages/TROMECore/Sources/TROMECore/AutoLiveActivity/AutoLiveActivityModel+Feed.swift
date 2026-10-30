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
        if showsExample {
            feedTask = Task { [weak self] in
                await self?.keepShowingTheExample()
            }
            return
        }
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
        var lastCall = configuration.now()
        var nextCall = fetchNow || waitsForItsTrains
            ? configuration.now()
            : nextPRIMCall(for: station, asksPRIM: asksPRIM)
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
            if redrawDate != nil, !(asksPRIM && asksInsteadOfRedrawing(at: station, lastCall: lastCall)) {
                await liveActivity.redraw()
                continue
            }
            let asked = asksPRIM
            if asksPRIM {
                lastCall = configuration.now()
                await feed(station, inPlaceOfARedraw: redrawDate != nil)
                asksPRIM = BackgroundTrainsRefresh.shouldAskAgain(after: inputs.liveActivityTrains.state(for: station))
            }
            nextCall = nextPRIMCall(for: station, asksPRIM: asksPRIM)
            if asked {
                logBackgroundCall(at: station, nextCall: asksPRIM ? nextCall : nil)
            }
        }
    }

    private func asksInsteadOfRedrawing(at station: Station, lastCall: Date) -> Bool {
        BackgroundTrainsRefresh.asksInsteadOfRedrawing(
            losesATrain: liveActivity.redrawLosesATrain(),
            after: inputs.liveActivityTrains.state(for: station),
            lastCall: lastCall,
            now: configuration.now()
        )
    }

    private func redrawAfterTheAnswerWait() -> Task<Void, Never> {
        Task { [weak self, sleep = configuration.sleep] in
            do {
                try await sleep(.seconds(BackgroundTrainsRefresh.answerWaitInPlaceOfARedraw))
            } catch {
                return
            }
            await self?.liveActivity.redraw()
        }
    }

    private var waitsForItsTrains: Bool {
        guard let content = liveActivity.content else { return true }
        return content.trains == .loading
    }

    private func nextPRIMCall(for station: Station, asksPRIM: Bool) -> Date {
        let now = configuration.now()
        guard asksPRIM else { return now.addingTimeInterval(BackgroundTrainsRefresh.maximumDelay) }
        return BackgroundTrainsRefresh.nextCall(
            after: inputs.liveActivityTrains.state(for: station),
            untilStale: liveActivity.content?.staleDate,
            now: now
        )
    }

    func keepFeeding(_ station: Station) async {
        while !Task.isCancelled {
            await feed(station)
            let trains = inputs.liveActivityTrains.state(for: station)
            do {
                try await configuration.sleep(
                    trains.refreshDelay(normally: NextTrainsModel.refreshInterval, now: configuration.now())
                )
            } catch {
                return
            }
        }
    }

    /// Asks for new times and shows them. A call made in place of a redraw still makes that redraw when its
    /// answer is slow or fails, so that the train that left never stays on the Live Activity for the whole call,
    /// and the kept times keep counting down until the next one leaves.
    func feed(_ station: Station, inPlaceOfARedraw: Bool = false) async {
        let trains = inputs.liveActivityTrains
        let redrawWhileTheAnswerIsLate = inPlaceOfARedraw ? redrawAfterTheAnswerWait() : nil
        await trains.refresh(for: station)
        redrawWhileTheAnswerIsLate?.cancel()
        guard !Task.isCancelled, shownStation?.id == station.id else { return }
        let state = trains.state(for: station)
        if inPlaceOfARedraw, case .failed = state {
            await liveActivity.redraw()
        }
        await liveActivity.update(station: station, trains: state)
    }

    public func screenTrainsChanged(for station: Station) async {
        guard shownStation?.id == station.id else { return }
        await liveActivity.update(station: station, trains: inputs.screenTrains.state(for: station))
    }

    func trains(for station: Station) -> NextTrainsState {
        if inputs.screenTrains.updatingStationId == station.id {
            return inputs.screenTrains.state(for: station)
        }
        return inputs.liveActivityTrains.state(for: station)
    }
}
