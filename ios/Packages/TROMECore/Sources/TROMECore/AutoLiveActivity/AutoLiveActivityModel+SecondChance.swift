import Foundation

extension AutoLiveActivityModel {
    /// After a refusal for lack of a trusted position, asks iOS again every few seconds (`ArrivalSecondChance`),
    /// and keeps the background location on meanwhile: without it, iOS suspends the app seconds after the wake.
    func giveASecondChance(to station: Station, reportedAt: Date) {
        guard inputs.automaticMode.allowsAutomaticStart, secondChances[station.id] == nil else { return }
        let chance = ArrivalSecondChance(station: station, reportedAt: reportedAt)
        secondChances[station.id] = chance
        services.wakeLog?.record(.decision, chance.startLine)
        services.locationKeeper.begin()
        guard secondChanceTask == nil else { return }
        secondChanceTask = Task { [weak self, sleep = configuration.sleep] in
            while true {
                do {
                    try await sleep(ArrivalSecondChance.interval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.takeASecondLook()
            }
        }
    }

    /// Any decision of the arrival rules on a station ends its second chance, whichever position it came from;
    /// so does the decision on a position that the second chance put within 150 m, even for a nearer station.
    func endSecondChances(on outcome: ArrivalOutcome?) {
        guard let outcome, let station = outcome.station else { return }
        for chance in openChances where chance.station == station || chance.isBeingDecided {
            end(chance, .outcome(outcome))
        }
    }

    func endSecondChance(leaving event: RegionEvent) {
        guard case .left(let regionId) = event,
              let stationId = WatchedRegion.arrivalStationId(inRegionId: regionId) ?? event.leftStopStationId,
              let chance = secondChances[stationId] else { return }
        end(chance, .left)
    }

    /// A snooze or the automatic mode turned off ends every second chance at once,
    /// so that the background location does not stay on for a start that cannot come.
    func endSecondChancesIfAutomaticStartIsOff() {
        guard !inputs.automaticMode.allowsAutomaticStart else { return }
        openChances.forEach { end($0, .automaticStartOff) }
    }

    private func takeASecondLook() async {
        guard inputs.locationService.source == .realGPS else {
            openChances.forEach { end($0, .fakePosition) }
            return
        }
        endSecondChancesIfAutomaticStartIsOff()
        for chance in openChances where chance.isOver(now: configuration.now()) {
            end(chance, .limit(lastPosition: inputs.locationService.fix))
        }
        guard !secondChances.isEmpty else { return }
        services.locationKeeper.begin()
        let fix = await freshPosition(waitingAtMost: ReportedArrivalRules.maximumWait)
        var isAtAStation = false
        for chance in openChances {
            switch chance.verdict(on: fix, now: configuration.now()) {
            case .atTheStation:
                secondChances[chance.station.id]?.isBeingDecided = true
                isAtAStation = true
            case .far(let meters): end(chance, .far(meters: meters))
            case .undecided: break
            }
        }
        guard let fix, isAtAStation else { return }
        await handle(fix.coordinate, logsEveryOutcome: true)
        for id in secondChances.keys {
            secondChances[id]?.isBeingDecided = false
        }
    }

    private var openChances: [ArrivalSecondChance] {
        secondChances.values.sorted { ($0.reportedAt, $0.station.name) < ($1.reportedAt, $1.station.name) }
    }

    private func end(_ chance: ArrivalSecondChance, _ end: ArrivalSecondChance.End) {
        secondChances[chance.station.id] = nil
        services.wakeLog?.record(.decision, chance.line(for: end, now: configuration.now()))
        guard secondChances.isEmpty else { return }
        secondChanceTask?.cancel()
        secondChanceTask = nil
        if state.shown == nil || !liveActivity.isShowing {
            services.locationKeeper.end()
        }
    }
}
