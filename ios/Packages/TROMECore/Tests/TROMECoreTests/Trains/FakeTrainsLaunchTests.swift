import Foundation
import Testing
@testable import TROMECore

struct FakeTrainsLaunchTests {
    private let executable = "/path/to/TROME"
    private let storage = InMemoryKeyValueStore()
    private let utc = TimeZone(identifier: "UTC")!
    private let launch = Date(timeIntervalSince1970: 1_000_000)

    private var store: FakeTrainsStore {
        FakeTrainsStore(storage: storage)
    }

    private func logLine(_ arguments: [String], at now: Date, hasTrainDataKey: Bool = false) -> String {
        store.launch(with: [executable] + arguments, at: now).logLine(hasTrainDataKey: hasTrainDataKey, timeZone: utc)
    }

    @Test func saysTheLaunchAskedForAStateAndTheAppUsesIt() {
        #expect(logLine(["--fake-trains", "at-platform"], at: launch)
            == "launch with arguments, --fake-trains at-platform | saved: no fake trains"
            + " | uses: fake trains at-platform from 13:46:40")
    }

    @Test func saysALaunchWithNoArgumentKeepsTheSavedState() {
        _ = store.launch(with: [executable, "--fake-trains", "ten-to-nine"], at: launch)

        #expect(logLine([], at: launch + 600)
            == "launch with no argument | saved: fake trains ten-to-nine from 13:46:40"
            + " | uses: fake trains ten-to-nine from 13:46:40")
    }

    @Test func saysTheStateItReplaces() {
        _ = store.launch(with: [executable, "--fake-trains", "ten-to-nine"], at: launch)

        #expect(logLine(["--fake-trains"], at: launch + 60)
            == "launch with arguments, --fake-trains | saved: fake trains ten-to-nine from 13:46:40"
            + " | uses: fake trains default from 13:47:40")
    }

    @Test func saysAStateItDoesNotKnowAndThatItUsesNoFakeTrains() {
        #expect(logLine(["--fake-trains", "at-plaform"], at: launch)
            == "launch with arguments, --fake-trains at-plaform (unknown state) | saved: no fake trains"
            + " | uses: no fake trains, no key: no data")
    }

    @Test func writesNoOtherArgumentSoNoSecretReachesTheLog() {
        let line = logLine(["-primAPIKey", "secret-value"], at: launch, hasTrainDataKey: true)

        #expect(line == "launch with arguments, no --fake-trains | saved: no fake trains"
            + " | uses: no fake trains, live trains of the key")
        #expect(!line.contains("secret-value"))
    }
}
