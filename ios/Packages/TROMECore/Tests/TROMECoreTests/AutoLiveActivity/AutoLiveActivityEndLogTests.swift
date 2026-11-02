import Foundation
import Testing
@testable import TROMECore

/// Each way that a Live Activity ends writes one line in the wake log, which says who ended it: after a walk, the
/// record alone tells a Live Activity that the rider or iOS removed from one that the app's rules ended.
extension AutoLiveActivityModelTests {
    private var endLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision && $0.text.hasPrefix("Live Activity ended") }.map(\.text)
    }

    private var decisionLines: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text)
    }

    @Test func aStopByHandSaysTheRiderStoppedIt() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.stopByHand()

        #expect(endLines == ["Live Activity ended by the rider: stopped by hand"])
    }

    @Test(arguments: [
        (SnoozeDuration.thirtyMinutes, "for 30 min"), (.oneHour, "for 1 h"), (.restOfToday, "for the rest of the day")
    ])
    func aSnoozeSaysTheRiderSnoozedItAndWritesNoStopLine(duration: SnoozeDuration, text: String) async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        await model.snooze(for: duration)

        #expect(endLines == ["Live Activity ended by the rider: snoozed \(text)"])
    }

    @Test func aSnoozeWithNoLiveActivityWritesNoEndLine() async {
        let model = makeModel()
        await activate(model)

        await model.snooze(for: .oneHour)

        #expect(endLines.isEmpty)
    }

    @Test func turningTheAutomaticStartOffSaysTheRiderTurnedItOff() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        automaticMode.setOn(false)
        await waitUntil { client.endCount == 1 }

        #expect(endLines == ["Live Activity ended by the rider: automatic start turned off"])
    }

    @Test func aSwipeSaysTheRiderSwipedItAwayOnce() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        swipeAway()
        await activate(model)

        #expect(endLines == ["Live Activity ended by the rider: swiped away (iOS: dismissed)"])
    }

    @Test func aSwipeThatTheAppSeesFirstAsAGoneLiveActivityWritesOneLine() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        client.isShowing = false
        removals.endState = .dismissed
        await activate(model)
        removals.report()

        #expect(endLines == ["Live Activity ended by the rider: swiped away (iOS: dismissed)"])
    }

    @Test func theEndLineOfASwipeComesBeforeTheNextStart() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)
        swipeAway()

        gps.report(Places.atB)
        await waitUntil { client.started.count == 2 }

        let end = decisionLines.firstIndex(of: "Live Activity ended by the rider: swiped away (iOS: dismissed)")
        let start = decisionLines.firstIndex(of: "Live Activity started: Station B")
        #expect(end != nil && start != nil)
        if let end, let start {
            #expect(start < end, "newest first: the start at B must be newer than the end at A")
        }
    }

    @Test(arguments: [
        (LiveActivityEndState.ended, true, "Live Activity ended by iOS (iOS: ended)"),
        (nil, true, "Live Activity ended outside the app: iOS gave no reason"),
        (.dismissed, false, "Live Activity ended by iOS: Live Activities are off in Settings (iOS: dismissed)")
    ])
    func anEndByIOSSaysWhatIOSGave(state: LiveActivityEndState?, enabled: Bool, line: String) async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        client.isShowing = false
        client.areActivitiesEnabled = enabled
        removals.endState = state
        await activate(model)

        #expect(endLines == [line])
    }

    @Test func anEndPastTheSystemLimitSaysIOSEndedIt() async {
        let model = makeModel()
        await arrive(at: Places.fiftyMetersFromA, in: model)

        clock.advance(by: AutoLiveActivityRules.systemMaximumDuration)
        client.isShowing = false
        removals.endState = .ended
        await activate(model)

        #expect(endLines == ["Live Activity ended by iOS: 8 h limit (iOS: ended)"])
    }

    @Test func aLiveActivityGoneSinceTheLastRunWritesItsLineAtLaunch() {
        let shown = AutoLiveActivityState.Shown(stationId: Places.stationA.id, startedAt: clock.now, hasBeenNear: true)
        AutoLiveActivityStore(storage: storage).save(AutoLiveActivityState(shown: shown))
        removals.endState = .dismissed

        let model = makeModel()

        #expect(endLines == ["Live Activity ended by the rider: swiped away (iOS: dismissed)"])
        withExtendedLifetime(model) {}
    }

    @Test func theEndLinesStayInTheBoundedLog() async {
        let model = makeModel()
        await activate(model)

        for _ in 0...WakeLog.maximumEntries {
            await model.startByHand(Places.stationA)
            await model.stopByHand()
        }

        #expect(wakeLog.entries.count == WakeLog.maximumEntries)
        #expect(endLines.first == "Live Activity ended by the rider: stopped by hand")
    }

    @Test func theEndLinesOfTheRiderAndOfIOSHoldNoPlaceAndNoNumberButADuration() {
        let states: [LiveActivityEndState?] = [nil, .ended, .dismissed]
        let outside: [LiveActivityEnding.OutsideEnd] = [
            .liveActivitiesTurnedOff, .systemLimit, .swipedAway, .endedByIOS, .noReason
        ]
        let endings: [LiveActivityEnding] = [.stoppedByHand, .automaticStartTurnedOff]
            + SnoozeDuration.allCases.map { .snoozed($0) }
            + outside.flatMap { end in states.map { .outsideTheApp(end, iOSState: $0) } }

        for line in endings.map(\.summary) {
            #expect(line.hasPrefix("Live Activity ended"))
            #expect(line.firstMatch(of: /\d+[.,]\d+/) == nil, "a coordinate: \(line)")
            #expect(line.replacing(/\d+ (h|min)/, with: "").firstMatch(of: /\d/) == nil, "a number: \(line)")
            #expect(!line.contains(Places.stationA.name))
        }
    }
}
