import Foundation
import Testing
@testable import TROMECore

/// The states of a start by the server's push, which the builds before 1.0.0 (4) cannot hold: so this file stays out
/// of the copy that records an older build (`PhoneSetRecorder`).
extension PhoneSetRecorder {
    @Test(.enabled(if: output != nil))
    func recordsAStartByThePush() async throws {
        let shown = try await Self.trains(of: Self.shownCase)
        let station = shown.station
        let startedAt = shown.now.addingTimeInterval(-Self.startedBefore)
        try record("live-activity-started-by-the-push", rider: [
            "automaticMode": "on",
            "arrivalStationId": station.id,
            "shown": [
                "stationId": station.id,
                "startedAt": Self.text(startedAt),
                "hasBeenNear": true,
                "isStartedByThePush": true
            ],
            "lastTimes": try Self.lastTimes(shown.trains, of: station)
        ]) { storage in
            _ = automaticMode(in: storage, now: shown.now)
            var state = AutoLiveActivityState(arrivalStationId: station.id)
            state.shown = .init(
                stationId: station.id,
                startedAt: startedAt,
                hasBeenNear: true,
                isStartedByThePush: true
            )
            AutoLiveActivityStore(storage: storage).save(state)
            StationLiveActivityInputsStore(storage: storage).save(.init(station: station, trains: shown.trains))
        }
        // The server took the start, and the app waits for the Live Activity that its push brings.
        let answeredAt = shown.now.addingTimeInterval(-10)
        try record("pushed-start", rider: [
            "pushedStart": ["stationId": station.id, "answeredAt": Self.text(answeredAt)]
        ]) { storage in
            var state = AutoLiveActivityState()
            state.pushedStart = PushedStart(stationId: station.id, answeredAt: answeredAt)
            AutoLiveActivityStore(storage: storage).save(state)
        }
    }
}
