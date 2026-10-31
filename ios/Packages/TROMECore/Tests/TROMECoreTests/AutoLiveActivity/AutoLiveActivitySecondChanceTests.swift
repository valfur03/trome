import Foundation
import Testing
@testable import TROMECore

/// iOS reports that the phone entered the area of a station, and the first position is too rough to trust:
/// cell towers only, a street between tall buildings. The app refuses the report, then asks iOS again for a while,
/// so that a rider who is really at the station still gets the notification.
extension AutoLiveActivityModelTests {
    enum FirstPosition: CaseIterable {
        case rough
        case none
    }

    private static let rough = 1_000.0

    private var decisionLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text).reversed()
    }

    private func enteredA(_ model: AutoLiveActivityModel, lastKnownFix: PositionFix? = nil) async {
        await model.handleRegionEvent(.entered(regionId: "arrival:a"), lastKnownFix: lastKnownFix)
    }

    /// The second chance asks iOS every 5 s of the test clock, and each ask takes about 20 ms of real time.
    private func waitForTheEnd(
        of model: AutoLiveActivityModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await waitUntil(sourceLocation: sourceLocation) { model.secondChances.isEmpty }
    }

    private func roughPositionsAtA() {
        clock.letTimersFire(upTo: 10)
        gps.currentFixCoordinate = Places.fiftyMetersFromA
        gps.currentFixAccuracyMeters = Self.rough
    }

    @Test(arguments: FirstPosition.allCases)
    func notifiesOnceWhenATrustedPositionAtTheStationComesAfterARoughOne(_ first: FirstPosition) async {
        let model = makeModel()
        roughPositionsAtA()
        gps.givesACurrentFix = first == .rough

        await enteredA(model)
        await enteredA(model)
        #expect(notifier.notified.isEmpty)
        gps.givesACurrentFix = true
        gps.currentFixAccuracyMeters = 10
        await waitForTheEnd(of: model)

        #expect(notifier.notified == [Places.stationA])
        #expect(client.started.isEmpty)
        #expect(!keeper.isKeeping)
        let firstReason = first == .rough ? "the position is ±1000 m and 0 s old" : "iOS gave no position"
        #expect(decisionLines.first == "No arrival at Station A: \(firstReason)")
        #expect(decisionLines.filter { $0.hasPrefix("Second chance at Station A: asks iOS") }.count == 1)
        #expect(decisionLines.contains { $0.hasPrefix("Second chance at Station A: notified after ") })

        await enteredA(model, lastKnownFix: PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 10,
                                                        timestamp: clock.now))
        await model.notificationTapped(stationId: "a")
        await activate(model)
        #expect(client.started.map(\.stationName) == ["Station A"])
        #expect(notifier.notified == [Places.stationA])
    }

    @Test(arguments: [false, true])
    func notifiesNoStationWhenTheTrustedPositionAfterARestartIsFar(hasAPositionFromBeforeTheRestart: Bool)
        async throws {
        let paris = try StationCatalog.bundled()
        let names = ["Magenta", "Gare du Nord", "Gambetta", "Mairie des Lilas", "Porte de Bagnolet", "Jourdain"]
        let stations = try names.map { name in try #require(paris.stations.first { $0.name == name }) }
        let riderPlace = Coordinate(48.8831, 2.416324)
        let beforeTheRestart = hasAPositionFromBeforeTheRestart
            ? PositionFix(coordinate: riderPlace, accuracyMeters: 10, timestamp: clock.now - 515)
            : nil
        let model = makeModel(catalog: paris)
        clock.letTimersFire(upTo: 10)
        gps.givesACurrentFix = false

        for station in stations {
            await model.handleRegionEvent(.entered(regionId: "arrival:\(station.id)"), lastKnownFix: beforeTheRestart)
        }
        #expect(model.secondChances.count == stations.count)
        gps.currentFixCoordinate = riderPlace
        gps.givesACurrentFix = true
        await waitForTheEnd(of: model)

        #expect(notifier.notified.isEmpty)
        #expect(client.started.isEmpty)
        #expect(!keeper.isKeeping)
        #expect(decisionLines.filter { $0.hasPrefix("Second chance at ") && $0.contains(": gave up after ") }.count
            == stations.count)
        #expect(decisionLines.contains {
            $0.hasPrefix("Second chance at Mairie des Lilas: gave up after ")
                && $0.hasSuffix(": the position is 377 m away")
        })
    }

    @Test func notifiesNothingWhenIOSSaysThatTheRiderLeftBeforeATrustedPosition() async {
        let model = makeModel()
        roughPositionsAtA()

        await enteredA(model)
        await model.handleRegionEvent(.left(regionId: "arrival:a"), lastKnownFix: nil)
        let asks = gps.currentFixRequestCount
        gps.currentFixAccuracyMeters = 10
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.secondChances.isEmpty)
        #expect(gps.currentFixRequestCount == asks)
        #expect(notifier.notified.isEmpty)
        #expect(!keeper.isKeeping)
        #expect(decisionLines.contains {
            $0.hasPrefix("Second chance at Station A: gave up after ")
                && $0.hasSuffix(" s: iOS says the phone left its area")
        })
    }

    @Test func notifiesNothingWhenTheFirstTrustedPositionIsPastTheStopArea() async {
        let model = makeModel()
        roughPositionsAtA()

        await enteredA(model)
        gps.currentFixCoordinate = Places.fourHundredMetersFromA
        gps.currentFixAccuracyMeters = 10
        await waitForTheEnd(of: model)

        #expect(notifier.notified.isEmpty)
        #expect(!keeper.isKeeping)
        #expect(decisionLines.contains {
            $0.hasPrefix("Second chance at Station A: gave up after ") && $0.hasSuffix(" s: the position is 400 m away")
        })
    }

    @Test func givesUpTwoMinutesAfterTheReportAndStopsAskingIOS() async {
        let model = makeModel()
        roughPositionsAtA()

        await enteredA(model)
        #expect(keeper.isKeeping)
        await waitForTheEnd(of: model)
        let asks = gps.currentFixRequestCount
        try? await Task.sleep(for: .milliseconds(100))

        #expect(gps.currentFixRequestCount == asks)
        #expect(asks <= 1 + Int(ArrivalSecondChance.limit) / 5)
        #expect(notifier.notified.isEmpty)
        #expect(!keeper.isKeeping)
        #expect(decisionLines.last == """
            Second chance at Station A: gave up after 120 s: the position is ±1000 m and 5 s old
            """)
    }

    @Test func keepsTheRuleOfTheSameArrivalAsBefore() async {
        AutoLiveActivityStore(storage: storage).save(AutoLiveActivityState(arrivalStationId: "a"))
        let model = makeModel()
        roughPositionsAtA()

        await enteredA(model)
        gps.currentFixAccuracyMeters = 10
        await waitForTheEnd(of: model)

        #expect(notifier.notified.isEmpty)
        #expect(decisionLines.contains { $0.hasPrefix("Second chance at Station A: ended after ") && $0.hasSuffix(
            ": No notification at Station A: same arrival as before, until you leave its 250 m area"
        ) })
    }

    @Test(arguments: [false, true])
    func endsTheSecondChanceAndTheBackgroundLocationWhenTheRiderSnoozesOrTurnsOff(turnsOff: Bool) async {
        let model = makeModel()
        roughPositionsAtA()

        await enteredA(model)
        #expect(keeper.isKeeping)
        let asksBefore = gps.currentFixRequestCount
        if turnsOff {
            automaticMode.setOn(false)
        } else {
            automaticMode.snooze(for: .oneHour)
        }
        await waitForTheEnd(of: model)
        let asks = gps.currentFixRequestCount
        gps.currentFixAccuracyMeters = 10
        try? await Task.sleep(for: .milliseconds(100))

        #expect(model.secondChances.isEmpty)
        #expect(gps.currentFixRequestCount == asks)
        #expect(asks <= asksBefore + 1)
        #expect(notifier.notified.isEmpty)
        #expect(!keeper.isKeeping)
        #expect(decisionLines.contains {
            $0.hasPrefix("Second chance at Station A: gave up after ")
                && $0.hasSuffix(" s: the automatic start is snoozed or off")
        })
    }

    @Test func givesNoSecondChanceWhenAutomaticStartIsSnoozed() async {
        let model = makeModel()
        roughPositionsAtA()
        automaticMode.snooze(for: .oneHour)

        await enteredA(model)

        #expect(model.secondChances.isEmpty)
        #expect(!keeper.isKeeping)
    }
}
