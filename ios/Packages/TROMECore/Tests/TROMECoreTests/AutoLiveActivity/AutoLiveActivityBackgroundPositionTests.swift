import Foundation
import Testing
@testable import TROMECore

/// The app follows the position away from the screen only while a Live Activity shows, or while it decides an
/// arrival that iOS reported. A rider who opened the app once and then rides with it in the background, with no
/// Live Activity, must cost no battery: no position, no new plan of the station areas, no wake.
extension AutoLiveActivityModelTests {
    /// A ride north from Station A, a point every 100 m.
    private static let rideNorth = (1...8).map { Coordinate(48.8536 + Double($0) * 0.0009, 2.3500) }

    private func openedThenSentToTheBackground(_ model: AutoLiveActivityModel) async {
        await activate(model)
        gps.report(Places.fourHundredMetersFromA)
        await waitUntil { !watcher.watched.isEmpty }
        model.setAppPhase(.background)
    }

    @Test func anAppOpenedOnceFollowsNoPositionInTheBackground() async {
        let model = makeModel()
        await openedThenSentToTheBackground(model)
        await waitUntil { !gps.isReporting }
        let plans = watcher.watched.count
        let lastFix = locationService.fix

        for point in Self.rideNorth + [Places.atB] {
            clock.advance(by: 10)
            gps.report(point)
        }

        await expectNever(for: .milliseconds(200)) {
            watcher.watched.count != plans || locationService.fix != lastFix || !notifier.notified.isEmpty
        }
        #expect(!keeper.isKeeping)
        #expect(client.started.isEmpty)
    }

    @Test func openingTheAppAgainFollowsThePositionAtOnce() async {
        let model = makeModel()
        await openedThenSentToTheBackground(model)
        await waitUntil { !gps.isReporting }

        await activate(model)
        gps.report(Places.fiftyMetersFromA)

        await waitUntil { client.isShowing }
        #expect(model.shownStation == Places.stationA)
    }

    @Test func aLiveActivityKeepsThePositionInTheBackgroundUntilTheRiderLeaves() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
        #expect(gps.isReporting)

        gps.report(Places.atB)
        await waitUntil { client.shownContent?.stationName == "Station B" }
        #expect(gps.isReporting)

        gps.report(Self.rideNorth[7])
        await waitUntil { client.endCount == 1 && !gps.isReporting }
        #expect(!keeper.isKeeping)
    }

    @Test func aStationReportWithTheAppInTheBackgroundStillNotifiesAndLeavesThePositionOff() async {
        let model = makeModel()
        await openedThenSentToTheBackground(model)
        await waitUntil { !gps.isReporting }
        let atA = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 10, timestamp: clock.now)

        await model.handleRegionEvent(.entered(regionId: "arrival:a"), lastKnownFix: atA)

        #expect(notifier.notified == [Places.stationA])
        #expect(!gps.isReporting)
        #expect(!keeper.isKeeping)
    }

    @Test func aStationReportWithNoTrustedPositionFollowsThePositionOnlyForItsSecondChance() async {
        let model = makeModel()
        await openedThenSentToTheBackground(model)
        await waitUntil { !gps.isReporting }
        gps.givesACurrentFix = false
        clock.letTimersFire(upTo: 10)

        await model.handleRegionEvent(.entered(regionId: "arrival:a"), lastKnownFix: nil)
        #expect(gps.isReporting)
        #expect(keeper.isKeeping)

        clock.letTimersFire(upTo: 200)
        await waitUntil { model.secondChances.isEmpty && !gps.isReporting }
        #expect(!keeper.isKeeping)
    }

    @Test func aWakeWithAnOldPositionAsksIOSForANewOneAndPlansTheAreasAgain() async {
        let model = makeModel()
        await openedThenSentToTheBackground(model)
        await waitUntil { !gps.isReporting }
        let plans = watcher.watched.count
        let farNorth = Self.rideNorth[7]
        let old = PositionFix(coordinate: Places.fourHundredMetersFromA, accuracyMeters: 10, timestamp: clock.now)
        clock.advance(by: 600)
        gps.currentFixCoordinate = farNorth

        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: old)

        #expect(gps.currentFixRequestCount == 1)
        #expect(watcher.watched.count == plans + 1)
        #expect(model.plannedRegions?.center == farNorth)
    }

    /// A line of 40 stations, one each kilometre, north from 48.80 N: more than the 18 areas of one plan.
    private static let line = StationCatalog(stations: (0..<40).map {
        Station(id: "s\($0)", name: "Station \($0)", coordinate: kilometre(Double($0)), lines: [])
    })

    private static func kilometre(_ km: Double) -> Coordinate {
        Coordinate(48.80 + km * 0.009, 2.3500)
    }

    private var watchedStationIds: Set<String> {
        Set((watcher.watched.last ?? []).compactMap { WatchedRegion.arrivalStationId(inRegionId: $0.id) })
    }

    private func fix(at km: Double) -> PositionFix {
        PositionFix(coordinate: Self.kilometre(km), accuracyMeters: 10, timestamp: clock.now)
    }

    /// The app is never on screen and follows no position: only the wakes of iOS move the plan of the areas, the
    /// exit of the area around the rider first, which is smaller than the farthest planned station, so the rider
    /// always leaves it before going past the plan. A relaunch by iOS keeps it going.
    @Test func aClosedAppPlansTheAreasAgainAtEachWakeAlongARideAndTheFarStationStillNotifies() async {
        let model = makeModel(catalog: Self.line)
        model.setAppPhase(.background)
        await waitUntil { !gps.isReporting }

        await model.handleRegionEvent(.entered(regionId: "arrival:s0"), lastKnownFix: fix(at: 0))
        #expect(notifier.notified.map(\.id) == ["s0"])
        #expect(watchedStationIds.contains("s17") && !watchedStationIds.contains("s25"))
        let refresh = watcher.watched.last?.first { $0.id == WatchedRegion.refreshId }
        #expect(refresh.map { $0.radiusMeters < Self.kilometre(0).distance(to: Self.kilometre(17)) } == true)

        clock.advance(by: 900)
        await model.handleRegionEvent(.left(regionId: "refresh"), lastKnownFix: fix(at: 16.5))
        #expect(watchedStationIds.contains("s25"))

        clock.advance(by: 300)
        let relaunched = makeModel(catalog: Self.line)
        relaunched.setAppPhase(.background)
        await relaunched.handleRegionEvent(.entered(regionId: "arrival:s25"), lastKnownFix: fix(at: 25))

        #expect(notifier.notified.map(\.id) == ["s0", "s25"])
        #expect(watchedStationIds.contains("s34"))
        #expect(!gps.isReporting)
        #expect(!keeper.isKeeping)
        withExtendedLifetime(model) {}
    }
}
