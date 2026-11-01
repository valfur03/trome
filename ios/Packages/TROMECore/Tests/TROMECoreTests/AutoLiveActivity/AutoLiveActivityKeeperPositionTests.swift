import Foundation
import Testing
@testable import TROMECore

/// A rider with the location Always and the phone in the pocket: iOS stops the position stream about 10 seconds after
/// the app leaves the screen, so the Live Activity switches and ends on the positions of the background keeper.
extension AutoLiveActivityModelTests {
    private func showAInTheBackground(_ model: AutoLiveActivityModel) async {
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
    }

    private var decisionLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text).reversed()
    }

    private func keeperFix(at coordinate: Coordinate) -> PositionFix {
        clock.advance(by: 1)
        return PositionFix(coordinate: coordinate, accuracyMeters: 10, timestamp: clock.now)
    }

    @Test func switchesAtTheNextStationOnAPositionOfTheKeeperWhenTheStreamIsSilent() async {
        let model = makeModel()
        await showAInTheBackground(model)

        keeper.report(keeperFix(at: Places.atB))
        await waitUntil { client.updates.last?.stationName == "Station B" }

        #expect(client.started.count == 1)
        #expect(notifier.notified.isEmpty)
        #expect(decisionLines.contains("Live Activity switched to Station B (position: keeper)"))
    }

    @Test func endsOnAPositionOfTheKeeperWhenTheStreamIsSilent() async {
        let model = makeModel()
        await showAInTheBackground(model)

        keeper.report(keeperFix(at: Places.fourHundredMetersFromA))
        await waitUntil { client.endCount == 1 }

        #expect(model.shownStation == nil)
        #expect(decisionLines.contains("Live Activity ended: 400 m from Station A (position: keeper)"))
    }

    @Test func saysThatTheStreamMovedTheLiveActivityWhileIOSStillSendsIt() async {
        let model = makeModel()
        await showAInTheBackground(model)

        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 }

        #expect(decisionLines.contains("Live Activity ended: 400 m from Station A (position: stream)"))
    }
}
