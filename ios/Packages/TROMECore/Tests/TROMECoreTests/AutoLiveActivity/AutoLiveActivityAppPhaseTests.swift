import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    @Test func startsTheLiveActivityOfAnArrivalUnderASystemQuestionOnceTheAppIsActiveAgain() async {
        let model = makeModel()
        await activate(model)
        model.setAppPhase(.inactive)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }
        #expect(client.started.isEmpty)
        clock.advance(by: 22)
        await activate(model)

        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(model.shownStation == Places.stationA)
        #expect(arrivalsWithNoStart.isEmpty)
    }

    @Test func arrivesAnArrivalUnderASystemQuestionWhenTheAppGoesToTheBackground() async {
        let model = makeModel()
        await activate(model)
        model.setAppPhase(.inactive)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }
        #expect(arrivalsWithNoStart.isEmpty)
        model.setAppPhase(.background)
        await waitUntil { !arrivalsWithNoStart.isEmpty }

        #expect(arrivalsWithNoStart == [Places.stationA.name])
        #expect(client.started.isEmpty)
    }
}
