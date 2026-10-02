import Foundation
import Testing
@testable import RATPCore

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
        #expect(notifier.notified.isEmpty)
    }

    @Test func notifiesAnArrivalUnderASystemQuestionWhenTheAppGoesToTheBackground() async {
        let model = makeModel()
        await activate(model)
        model.setAppPhase(.inactive)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }
        #expect(notifier.notified.isEmpty)
        model.setAppPhase(.background)
        await waitUntil { !notifier.notified.isEmpty }

        #expect(notifier.notified == [Places.stationA])
        #expect(client.started.isEmpty)
    }
}
