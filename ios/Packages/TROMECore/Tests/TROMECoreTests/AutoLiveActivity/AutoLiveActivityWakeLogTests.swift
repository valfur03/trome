import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    private var decisions: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text)
    }

    @Test func logsTheNotificationOfARegionWake() async {
        let model = makeModel()

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(decisions == ["Notified: Station A"])
        #expect(wakeLog.entries.contains { $0.kind == .regions })
    }

    @Test func logsWhyASecondWakeAtTheSameStationGivesNoNotification() async {
        let model = makeModel()
        await wake(model, at: Places.fiftyMetersFromA)

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(notifier.notified == [Places.stationA])
        #expect(decisions.first?.hasPrefix("No notification at Station A: same arrival as before") == true)
    }

    @Test func logsAWakeWithAPositionTooOldToDecide() async {
        let model = makeModel()
        let old = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: clock.now - 600)

        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: old)

        #expect(decisions == ["No decision: the last position is 600 s old"])
    }

    @Test func logsAWakeWithAPositionTooRoughToTrust() async {
        let model = makeModel()
        let rough = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 400, timestamp: clock.now - 30)

        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: rough)

        #expect(decisions == ["No decision: position not trusted, ±400 m and 30 s old (needs ±100 m and 120 s)"])
        #expect(notifier.notified.isEmpty)
    }

    @Test func logsThatAFakePositionMakesTheAppIgnoreAWake() async {
        let model = makeModel()
        locationService.use(.fake(Places.stationB.fakePosition))

        await wake(model, at: Places.fiftyMetersFromA)

        #expect(decisions == ["Ignored: a fake position is on"])
    }

    @Test func logsEachReasonOnceWhileTheAppFollowsThePosition() async {
        let model = makeModel()
        await activate(model)

        gps.report(Places.fiftyMetersFromA)
        await waitUntil { client.isShowing }
        await model.handle(Places.fiftyMetersFromA)
        await model.handle(Places.fiftyMetersFromA)
        await model.handle(Places.twoHundredMetersFromA)
        await model.handle(Places.fourHundredMetersFromA)

        #expect(decisions == [
            "Live Activity ended: 400 m from Station A",
            "No station within 150 m: nearest is Station A, 200 m",
            "No notification at Station A: its Live Activity shows",
            "Live Activity started: Station A"
        ])
    }

    @Test func logsWhenTheAppComesOnScreenAndLeavesItButNotAPopup() {
        let model = makeModel()

        model.setAppPhase(.active)
        model.setAppPhase(.inactive)
        model.setAppPhase(.active)
        model.setAppPhase(.background)

        let screenChanges = wakeLog.entries.filter { $0.kind == .launch }.map(\.text)
        #expect(screenChanges == ["App in the background", "App on screen"])
    }

    /// A background call writes what answered and when the app asks again, so that the next outing can tell
    /// an app that iOS did not run from a source that answered old times or an answer that was not drawn.
    @Test func logsEachCallForTheLiveActivityInTheBackgroundWithItsAnswer() async throws {
        let line12 = TransitLine(mode: .metro, name: "12")
        let station = Station(id: "m", name: "Station M", coordinate: Coordinate(48.8600, 2.3600), lines: [line12])
        let train = clock.now.addingTimeInterval(300)
        provider.answer(.success([Departure(line: line12, destination: "Mairie d'Issy", time: train)]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { $0.trains.linesPage != nil } }
        #expect(!wakeLog.entries.contains { $0.kind == .trains })

        model.setAppPhase(.background)
        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { wakeLog.entries.contains { $0.kind == .trains } }
        provider.answer(.failure(.unreachable), for: station)
        clock.letTimersFire(upTo: 2 * BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { wakeLog.entries.filter { $0.kind == .trains }.count == 2 }

        let lines = wakeLog.entries.filter { $0.kind == .trains }.map(\.text)
        try #require(lines.count == 2)
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        let firstTrain = "12 Mairie d'Issy \(time.string(from: train))"
        #expect(lines[1].hasPrefix("Asked for Station M: answer 0 s old, \(firstTrain); next ask by "))
        #expect(lines[0].hasPrefix("Asked for Station M: no answer (unreachable); next ask by "))
    }
}
