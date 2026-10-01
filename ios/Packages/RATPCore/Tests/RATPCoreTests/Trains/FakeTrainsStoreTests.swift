import Foundation
import Testing
@testable import RATPCore

struct FakeTrainsStoreTests {
    private let executable = "/path/to/RATPActivity"
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
}
