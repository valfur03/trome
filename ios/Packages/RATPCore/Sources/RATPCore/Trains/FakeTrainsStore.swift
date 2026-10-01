#if DEBUG
import Foundation

public struct FakeTrainsStore {
    static let key = "testingTools.fakeTrains"

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    public func provider(forLaunchWith launchArguments: [String]) -> FakeDeparturesProvider? {
        let launchedByTheHarness = launchArguments.count > 1
        if launchedByTheHarness {
            save(launchArguments.contains(FakeDeparturesProvider.launchArgument))
        }
        return load() ? FakeDeparturesProvider() : nil
    }

    private func load() -> Bool {
        guard let data = storage.data(forKey: Self.key) else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    private func save(_ fakeTrains: Bool) {
        storage.set(try? JSONEncoder().encode(fakeTrains), forKey: Self.key)
    }
}
#endif
