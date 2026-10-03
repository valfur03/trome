import Foundation
import Testing
@testable import TROMECore

@MainActor
struct AutomaticModeModelTests {
    private let storage = InMemoryKeyValueStore()
    private let clock = TestClock()

    private func makeModel() -> AutomaticModeModel {
        let clock = clock
        return AutomaticModeModel(
            store: AutomaticModeStore(storage: storage),
            now: { clock.now },
            sleep: { try await clock.sleep(for: $0) }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func isOnAtFirstLaunch() {
        let model = makeModel()

        #expect(model.mode == .turnedOn)
        #expect(model.allowsAutomaticStart)
    }

    @Test func snoozesAndRemembersTheSnoozeAfterARelaunch() {
        let model = makeModel()

        model.snooze(for: .thirtyMinutes)

        let end = clock.now.addingTimeInterval(30 * 60)
        #expect(model.mode == .snoozed(until: end))
        #expect(model.allowsAutomaticStart == false)
        #expect(makeModel().mode == .snoozed(until: end))
    }

    @Test func isOnAgainByItselfOnceTheSnoozeEnds() async {
        clock.letTimersFire()
        let model = makeModel()

        model.snooze(for: .oneHour)
        await waitUntil { model.mode == .turnedOn }

        #expect(model.mode == .turnedOn)
        #expect(makeModel().mode == .turnedOn)
    }

    @Test func allowsAutomaticStartOnceTheSnoozeTimeHasPassedEvenBeforeItsTimerFires() {
        let model = makeModel()
        model.snooze(for: .thirtyMinutes)

        clock.advance(by: 30 * 60)

        #expect(model.allowsAutomaticStart)
    }

    @Test func isOnAtLaunchWhenTheSnoozeEndedWhileTheAppWasClosed() {
        makeModel().snooze(for: .thirtyMinutes)
        clock.advance(by: 31 * 60)

        #expect(makeModel().mode == .turnedOn)
    }

    @Test func cancelsTheSnooze() {
        let model = makeModel()
        model.snooze(for: .restOfToday)

        model.cancelSnooze()

        #expect(model.mode == .turnedOn)
        #expect(makeModel().mode == .turnedOn)
    }

    @Test func turnsOffUntilTurnedOnAgain() {
        let model = makeModel()
        model.snooze(for: .oneHour)

        model.setOn(false)
        #expect(model.mode == .turnedOff)
        model.cancelSnooze()
        model.snooze(for: .thirtyMinutes)
        #expect(makeModel().mode == .turnedOff)

        model.setOn(true)
        #expect(model.mode == .turnedOn)
        #expect(model.allowsAutomaticStart)
    }
}
