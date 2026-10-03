import Foundation

extension AutoLiveActivityModel {
    func positionForAResume() async -> PositionFix? {
        let held = inputs.locationService.fix
        guard inputs.locationService.source == .realGPS else {
            if let held { return held }
            return await freshPosition()
        }
        let heldAt = configuration.now()
        if ResumePositionRules.usesWithoutWaiting(held, now: heldAt) {
            Self.logPause("resume: the held position is \(describe(held, now: heldAt)), it uses it with no wait")
            return held
        }
        let fresh = await freshPosition()
        let now = configuration.now()
        let position = ResumePositionRules.position(fresh: fresh, held: held, now: now)
        Self.logPause(
            "resume: the held position is \(describe(held, now: now)), "
                + "iOS gave \(fresh.map { describe($0, now: now) } ?? "no position within 5 s"), "
                + "it uses \(position == nil ? "no position" : position == fresh ? "the one of iOS" : "the held one")"
        )
        return position
    }

    var arrivalResponse: AutoLiveActivityRules.ArrivalResponse {
        AutoLiveActivityRules.ArrivalResponse(
            appPhase: appPhase,
            allowsAutomaticStart: inputs.automaticMode.allowsAutomaticStart
        )
    }

    func resumeOpenArrival() async {
        guard waitsForAResume, let stationId = state.openArrivalStationId else { return }
        Self.logPause("resume: the app is open after an arrival at \(stationId) that was only notified")
        let position = await positionForAResume()
        guard waitsForAResume else { return }
        await resume(at: position)
    }

    private var waitsForAResume: Bool {
        configuration.rules.waitsForAResume(state: state, now: configuration.now(), onArrival: arrivalResponse)
    }

    func resume(at position: PositionFix?) async {
        cannotFindPosition = position == nil && appIsActive
        guard let position else { return }
        await handle(position.coordinate)
    }

    private func freshPosition() async -> PositionFix? {
        let locationService = inputs.locationService
        let sleep = configuration.sleep
        return await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            let timeout = Task {
                try? await sleep(ResumePositionRules.maximumWait)
                answer.give(nil)
            }
            Task {
                answer.give(await locationService.requestCurrentFix())
                timeout.cancel()
            }
        }
    }

    private func describe(_ fix: PositionFix?, now: Date) -> String {
        guard let fix else { return "none" }
        return "\(Int(now.timeIntervalSince(fix.timestamp))) s old with accuracy \(Int(fix.accuracyMeters)) m"
    }
}

@MainActor
private final class FirstAnswer {
    private var continuation: CheckedContinuation<PositionFix?, Never>?

    init(_ continuation: CheckedContinuation<PositionFix?, Never>) {
        self.continuation = continuation
    }

    func give(_ fix: PositionFix?) {
        continuation?.resume(returning: fix)
        continuation = nil
    }
}
