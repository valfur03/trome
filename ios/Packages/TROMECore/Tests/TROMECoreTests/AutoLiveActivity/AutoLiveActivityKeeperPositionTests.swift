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
    }

    @Test func endsOnAPositionOfTheKeeperWhenTheStreamIsSilent() async {
        let model = makeModel()
        await showAInTheBackground(model)

        keeper.report(keeperFix(at: Places.fourHundredMetersFromA))
        await waitUntil { client.endCount == 1 }

        #expect(model.shownStation == nil)
    }
}
