import Foundation
import Testing
@testable import TROMECore

/// When the app may be suspended (it goes to the background, a Live Activity ends), the Wake log says what iOS holds
/// for the area of the nearest station and whether anything keeps the app awake, with a bounded number of lines.
extension AutoLiveActivityModelTests {
    private var holdLines: [String] {
        wakeLog.entries.filter(RegionHoldLine.isHoldLine).map(\.text)
    }

    private func leaveTheScreen(_ model: AutoLiveActivityModel) {
        model.setAppPhase(.active)
        model.setAppPhase(.background)
    }

    @Test func saysWhatIOSHoldsForTheNearestStationWhenTheAppGoesToTheBackground() async {
        watcher.held = [
            "arrival:a": RegionHold(state: .inside, since: clock.now - 600),
            "arrival:b": RegionHold(state: .outside, since: clock.now - 900)
        ]
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { locationService.position == Places.twoHundredMetersFromA }
        let calls = provider.callCount

        leaveTheScreen(model)
        await waitUntil { !holdLines.isEmpty }

        #expect(holdLines.count == 1)
        #expect(holdLines.first?.hasPrefix("iOS holds Station A as inside since ") == true)
        #expect(holdLines.first?.hasSuffix(
            " (a walk back in wakes nothing); nothing keeps the app awake: iOS can suspend it"
        ) == true)
        #expect(wakeLog.entries.firstIndex(where: RegionHoldLine.isHoldLine)
            ?? 0 < wakeLog.entries.firstIndex { $0.text == "App in the background" } ?? 0)
        #expect(provider.callCount == calls, "the line asks nothing outside the phone")
    }

    @Test func writesOneLineForManyMovesToTheBackgroundWithNothingChanged() async {
        watcher.held = ["arrival:a": RegionHold(state: .inside, since: clock.now - 600)]
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { locationService.position == Places.twoHundredMetersFromA }

        for move in 1...5 {
            leaveTheScreen(model)
            await waitUntil { watcher.holdsReadCount == move }
        }
        #expect(holdLines.count == 1)
        watcher.held = ["arrival:a": RegionHold(state: .outside, since: clock.now)]
        leaveTheScreen(model)
        await waitUntil { holdLines.first?.contains("as outside") == true }

        #expect(holdLines.count == 2)
        #expect(holdLines.last?.contains("as inside") == true)
    }

    @Test func keepsOnlyTheNewestLinesWhenWhatIOSHoldsKeepsChanging() async {
        let model = makeModel()
        gps.report(Places.twoHundredMetersFromA)
        await waitUntil { locationService.position == Places.twoHundredMetersFromA }

        for move in 0..<(RegionHoldLine.maximumLines + 5) {
            let state: RegionHold.State = move.isMultiple(of: 2) ? .inside : .outside
            watcher.held = ["arrival:a": RegionHold(state: state, since: clock.now)]
            leaveTheScreen(model)
            await waitUntil { holdLines.count == min(move + 1, RegionHoldLine.maximumLines)
                && holdLines.first?.contains("as \(state.rawValue)") == true }
        }

        #expect(holdLines.count == RegionHoldLine.maximumLines)
        #expect(wakeLog.entries.filter { $0.text == "App in the background" }.count == RegionHoldLine.maximumLines + 5)
    }

    @Test func saysThatTheKeeperKeepsTheAppAwakeThenThatNothingDoesOnceTheLiveActivityEnds() async {
        watcher.held = ["arrival:a": RegionHold(state: .inside, since: clock.now)]
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        model.setAppPhase(.background)
        await waitUntil { !holdLines.isEmpty }
        #expect(holdLines.first?.hasSuffix("; kept awake by the position keeper") == true)

        await model.stopByHand()
        await waitUntil { holdLines.count == 2 }

        #expect(!keeper.isKeeping)
        #expect(holdLines.first?.hasSuffix("; nothing keeps the app awake: iOS can suspend it") == true)
    }

    @Test func writesNoHoldLineWithAFakePosition() async {
        let model = makeModel()
        locationService.use(.fake(Places.stationB.fakePosition))

        leaveTheScreen(model)
        await expectNever(for: .milliseconds(200)) { !holdLines.isEmpty }
    }

    /// The privacy promise of `ios/guide/testing-tools.md`: "The text holds the lines and Phone now, with distances to
    /// stations and never a position." These lines name a station and a time, never a coordinate or a key.
    @Test func theSharedRecordOfTheHoldLinesHoldsNoCoordinate() async {
        let catalog = StationCatalog(stations: [Self.leParc, Places.stationA])
        watcher.held = [
            "arrival:\(Self.leParc.id)": RegionHold(state: .inside, since: clock.now - 251),
            "arrival:a": RegionHold(state: .outside, since: nil)
        ]
        let model = makeModel(catalog: catalog)
        await arrive(at: Self.leParcEdge, in: model)
        model.setAppPhase(.background)
        await waitUntil { !holdLines.isEmpty }
        await model.stopByHand()
        await waitUntil { holdLines.count == 2 }

        let report = wakeLog.report(phone: ["Location: Always, precise"])

        #expect(report.contains("iOS holds Le Parc de Saint-Maur as inside since "))
        #expect(report.firstMatch(of: /\d+[.,]\d{3,}/) == nil, "a coordinate in the shared record: \(report)")
        for degrees in [Self.leParcEdge.latitude, Self.leParcEdge.longitude] {
            #expect(!report.contains(String(format: "%.2f", degrees)))
        }
        for line in holdLines {
            #expect(line.firstMatch(of: /[A-Za-z0-9]{24,}/) == nil, "a key-like token: \(line)")
        }
    }
}
