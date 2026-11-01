import Foundation
import Testing
@testable import TROMECore

/// A rider with the phone in the pocket: with the location Always, iOS stops the position stream about 10 seconds after
/// the app leaves the screen, so the Live Activity switches and ends on the positions of the background keeper.
/// Both sources often run at once and give the same position, so the wake log says how old the stream was, not only
/// which source came first.
extension AutoLiveActivityModelTests {
    private var decisionLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text).reversed()
    }

    private func showAInTheBackground(_ model: AutoLiveActivityModel) async {
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
    }

    private func keeperFix(at coordinate: Coordinate) -> PositionFix {
        clock.advance(by: 1)
        return PositionFix(coordinate: coordinate, accuracyMeters: 10, timestamp: clock.now)
    }

    /// iOS stopped the stream: its last position is from before the 3 minutes in the pocket.
    private func streamStopsInThePocket() {
        clock.advance(by: 180)
    }

    @Test func switchesAtTheNextStationOnAPositionOfTheKeeperWhenTheStreamIsSilent() async {
        let model = makeModel()
        await showAInTheBackground(model)
        streamStopsInThePocket()

        keeper.report(keeperFix(at: Places.atB))
        await waitUntil { client.updates.last?.stationName == "Station B" }

        #expect(client.started.count == 1)
        #expect(notifier.notified.isEmpty)
        #expect(decisionLines.contains("Live Activity switched to Station B (position: keeper; stream 181 s old)"))
    }

    @Test func endsOnAPositionOfTheKeeperWhenTheStreamIsSilent() async {
        let model = makeModel()
        await showAInTheBackground(model)
        streamStopsInThePocket()

        keeper.report(keeperFix(at: Places.fourHundredMetersFromA))
        await waitUntil { client.endCount == 1 }

        #expect(model.shownStation == nil)
        let ending = "Live Activity ended: 400 m from Station A (position: keeper; stream 181 s old)"
        #expect(decisionLines.contains(ending))
    }

    /// Both sources run, and the keeper gives the position first: the line still shows that the stream ran.
    @Test func saysThatTheStreamStillRanWhenTheKeeperComesFirst() async {
        let model = makeModel()
        await showAInTheBackground(model)
        clock.advance(by: 30)
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { locationService.position == Places.twoHundredMetersFromA }

        keeper.report(keeperFix(at: Places.fourHundredMetersFromA))
        await waitUntil { client.endCount == 1 }

        #expect(decisionLines.contains("Live Activity ended: 400 m from Station A (position: keeper; stream 1 s old)"))
    }

    @Test func saysThatTheStreamMovedTheLiveActivityWhenItComesFirst() async {
        let model = makeModel()
        await showAInTheBackground(model)

        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 }

        #expect(decisionLines.contains("Live Activity ended: 400 m from Station A (position: stream)"))
    }
}
