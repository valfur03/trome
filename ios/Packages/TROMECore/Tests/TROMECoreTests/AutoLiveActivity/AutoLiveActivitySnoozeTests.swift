import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    @Test func snoozeEndsTheLiveActivity() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.snooze(for: .thirtyMinutes)
        await waitUntil { !client.isShowing }

        #expect(client.isShowing == false)
        #expect(model.shownStation == nil)
        #expect(keeper.isKeeping == false)
        #expect(automaticMode.mode == .snoozed(until: clock.now.addingTimeInterval(30 * 60)))
    }

    @Test func startsNothingWhileSnoozed() async {
        let model = makeModel()
        await model.snooze(for: .oneHour)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { locationService.position == Places.fiftyMetersFromA }
        await wake(model, at: Places.atB)
        await activate(model)
        gps.report(Places.fiftyMetersFromA)
        await wake(model, at: Places.fiftyMetersFromA)

        #expect(arrivalsWithNoStart.isEmpty)
        #expect(client.started.isEmpty)
    }

    @Test func arrivesAgainOnceTheSnoozeEnds() async {
        let model = makeModel()
        await model.snooze(for: .thirtyMinutes)
        await wake(model, at: Places.fiftyMetersFromA)

        clock.advance(by: 30 * 60)
        await wake(model, at: Places.atB)

        #expect(arrivalsWithNoStart == [Places.stationB.name])
    }

    @Test func startsNothingWhileOff() async {
        let model = makeModel()
        automaticMode.setOn(false)

        await wake(model, at: Places.fiftyMetersFromA)
        await activate(model)
        await wake(model, at: Places.atB)

        #expect(arrivalsWithNoStart.isEmpty)
        #expect(client.started.isEmpty)
    }

    @Test(arguments: [false, true])
    func startsByHandWhileSnoozedOrOff(isOff: Bool) async {
        let model = makeModel()
        if isOff {
            automaticMode.setOn(false)
        } else {
            await model.snooze(for: .restOfToday)
        }

        await model.startByHand(Places.stationA)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
    }
}
