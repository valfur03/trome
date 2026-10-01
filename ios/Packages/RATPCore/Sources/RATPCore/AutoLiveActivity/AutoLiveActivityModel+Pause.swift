import Foundation
#if DEBUG
import os

private let pauseLogger = Logger(subsystem: "RATPActivity", category: "LiveActivity")
#endif

extension AutoLiveActivityModel {
    func watchLiveActivityRemovals() {
        services.liveActivityRemovals.watchRemovals { [weak self] removal in
            self?.liveActivityWasRemoved(removal)
        }
    }

    func liveActivityWasRemoved(_ removal: LiveActivityRemoval) {
        guard !removal.endedByTheApp else { return }
        syncWithSystem()
        let removed = removedOutsideTheApp
        removedOutsideTheApp = nil
        guard !liveActivity.isShowing else { return }
        let outcome = configuration.rules.outcome(of: removal, shown: removed, now: configuration.now())
        guard case .pause(let pause) = outcome else {
            Self.logPause("removal outside the app, no pause: \(outcome)")
            return
        }
        let replaced = state.pause.map { ", it replaces the pause at \($0.stationId)" } ?? ""
        state.pause = pause
        Self.logPause(
            "pause starts at \(pause.stationId) until \(pause.end), "
                + "reason: the rider removed the Live Activity\(replaced)"
        )
    }

    func endPause(at stationId: String, reason: String) {
        guard state.pause?.stationId == stationId else { return }
        state.pause = nil
        Self.logPause("pause at \(stationId) ends, reason: \(reason)")
    }

    func endPauseIfOver() {
        guard let pause = state.pause, !pause.isActive(at: configuration.now()) else { return }
        endPause(at: pause.stationId, reason: "the hour is over")
    }

    func schedulePauseEnd() {
        pauseTimerTask?.cancel()
        pauseTimerTask = nil
        guard let pause = state.pause else { return }
        let remaining = max(0, pause.end.timeIntervalSince(configuration.now()))
        pauseTimerTask = Task { [weak self, sleep = configuration.sleep] in
            do {
                try await sleep(.seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            endPauseIfOver()
            if state.pause == pause {
                schedulePauseEnd()
            }
        }
    }

    private static func logPause(_ event: String) {
        #if DEBUG
        pauseLogger.notice("\(event, privacy: .public)")
        #endif
    }
}
