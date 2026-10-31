import Foundation
import Testing
@testable import TROMECore

/// A rider who moves past stations with the app in the background: the Live Activity switches at the next station
/// with no notification, also when iOS wakes the app for the area of that station; and the wake log says when it
/// ended on the way, so that the next station notifies.
extension AutoLiveActivityModelTests {
    enum ReportedPosition: CaseIterable {
        case lastKnown
        case askedFromIOS
    }

    private var decisionLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text).reversed()
    }

    private func showAInTheBackground(_ model: AutoLiveActivityModel) async {
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
    }

    @Test(arguments: ReportedPosition.allCases)
    func switchesWithNoNotificationWhenIOSReportsTheNextStationWhileTheLiveActivityShows(
        _ position: ReportedPosition
    ) async {
        let model = makeModel()
        await showAInTheBackground(model)
        clock.letTimersFire(upTo: 10)
        gps.currentFixCoordinate = Places.atB
        let atB = PositionFix(coordinate: Places.atB, accuracyMeters: 10, timestamp: clock.now)

        await model.handleRegionEvent(
            .entered(regionId: "arrival:b"), lastKnownFix: position == .lastKnown ? atB : nil
        )

        #expect(client.updates.last?.stationName == "Station B")
        #expect(client.started.count == 1)
        #expect(notifier.notified.isEmpty)
        #expect(decisionLines.contains("Live Activity switched to Station B"))
    }

    @Test func logsWhyTheNextStationNotifiesWhenTheLiveActivityEndedOnTheWay() async {
        let model = makeModel()
        await showAInTheBackground(model)

        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { client.endCount == 1 }
        gps.report(Places.atB)
        await waitUntil { !notifier.notified.isEmpty }

        #expect(notifier.notified == [Places.stationB])
        #expect(decisionLines.suffix(3) == [
            "Live Activity ended: 400 m from Station A",
            "No station within 150 m: nearest is Station A, 400 m",
            "Notified: Station B"
        ])
    }

    @Test func logsTheEndOfTheLiveActivityAfterTheTimeLimit() async {
        clock.letTimersFire()
        let model = makeModel()
        await activate(model)
        gps.report(Places.fiftyMetersFromA)

        // The timer ends it 20 ms after the start, so wait for what stays: a start, then an end.
        await waitUntil { client.started.count == 1 && client.endCount == 1 }

        #expect(decisionLines.last == "Live Activity ended: 45 min after it started")
    }

    @Test func logsTheEndAtTheTimeLimitBeforeTheNotificationOfTheNextStation() async {
        let model = makeModel()
        await showAInTheBackground(model)
        clock.advance(by: 45 * 60)

        await model.handle(Places.atB)

        #expect(notifier.notified == [Places.stationB])
        #expect(decisionLines.suffix(2) == ["Live Activity ended: 45 min after it started", "Notified: Station B"])
    }
}
