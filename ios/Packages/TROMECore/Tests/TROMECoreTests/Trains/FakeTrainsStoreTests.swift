import Foundation
import Testing
@testable import TROMECore

struct FakeTrainsStoreTests {
    private let executable = "/path/to/TROME"
    private let storage = InMemoryKeyValueStore()

    private var store: FakeTrainsStore {
        FakeTrainsStore(storage: storage)
    }

    @Test func givesNoFakeTrainsWhenNothingAskedForThem() {
        #expect(store.provider(forLaunchWith: [executable]) == nil)
    }

    @Test func givesFakeTrainsWhenTheHarnessAsksForThem() {
        #expect(store.provider(forLaunchWith: [executable, FakeDeparturesProvider.launchArgument]) != nil)
    }

    @Test func keepsTheFakeTrainsWhenIOSLaunchesTheAppWithNoArgument() {
        let harnessLaunch = [executable, "--reset-location-source", FakeDeparturesProvider.launchArgument]
        _ = store.provider(forLaunchWith: harnessLaunch)

        #expect(store.provider(forLaunchWith: [executable]) != nil)
        #expect(store.provider(forLaunchWith: [executable]) != nil)
    }

    @Test func dropsTheFakeTrainsWhenTheHarnessLaunchesTheAppWithoutThem() {
        _ = store.provider(forLaunchWith: [executable, FakeDeparturesProvider.launchArgument])

        #expect(store.provider(forLaunchWith: [executable, "--reset-location-source"]) == nil)
        #expect(store.provider(forLaunchWith: [executable]) == nil)
    }

    @Test func dropsTheFakeTrainsForAnyOtherLaunchArgument() {
        _ = store.provider(forLaunchWith: [executable, FakeDeparturesProvider.launchArgument])

        #expect(store.provider(forLaunchWith: [executable, "-liveActivityMaximumDuration", "60"]) == nil)
    }

    @Test func savesTheScenarioThatTheHarnessAsksForAndWhenItStarted() {
        let launch = Date(timeIntervalSince1970: 1_000_000)
        let provider = store.provider(forLaunchWith: [executable, "--fake-trains", "at-platform"], at: launch)

        #expect(provider?.scenario == .atPlatform)
        #expect(provider?.start == launch)
    }

    @Test func keepsTheScenarioAndItsStartWhenIOSLaunchesTheAppWithNoArgument() {
        let launch = Date(timeIntervalSince1970: 1_000_000)
        _ = store.provider(forLaunchWith: [executable, "--fake-trains", "ten-to-nine"], at: launch)

        let relaunched = store.provider(forLaunchWith: [executable], at: launch.addingTimeInterval(600))

        #expect(relaunched?.scenario == .tenToNine)
        #expect(relaunched?.start == launch)
    }

    @Test func startsTheScenarioAgainAtEachLaunchByTheHarness() {
        let launch = Date(timeIntervalSince1970: 1_000_000)
        _ = store.provider(forLaunchWith: [executable, "--fake-trains", "at-platform"], at: launch)

        let again = store.provider(forLaunchWith: [executable, "--fake-trains", "at-platform-both"], at: launch + 600)

        #expect(again?.scenario == .atPlatformBoth)
        #expect(again?.start == launch.addingTimeInterval(600))
    }

    @Test func givesTheFakeTrainsWithTimesFromNowWhenAnotherArgumentFollows() {
        let provider = store.provider(forLaunchWith: [executable, "--fake-trains", "--reset-location-source"])

        #expect(provider != nil)
        #expect(provider?.scenario == nil)
    }

    @Test func givesNoFakeTrainsForAScenarioItDoesNotKnow() {
        _ = store.provider(forLaunchWith: [executable, "--fake-trains"])

        #expect(store.provider(forLaunchWith: [executable, "--fake-trains", "at-plaform"]) == nil)
        #expect(store.provider(forLaunchWith: [executable]) == nil)
    }
}
