#if DEBUG
import Foundation

public struct FakeTrainsStore {
    static let key = "testingTools.fakeTrains"

    struct Choice: Codable, Equatable {
        var scenario: FakeTrainsScenario?
        var start: Date
    }

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    public func provider(forLaunchWith launchArguments: [String], at now: Date = Date()) -> FakeDeparturesProvider? {
        let launchedByTheHarness = launchArguments.count > 1
        if launchedByTheHarness {
            save(Self.choice(askedBy: launchArguments, at: now))
        }
        return load().map { FakeDeparturesProvider(scenario: $0.scenario, start: $0.start) }
    }

    static func choice(askedBy launchArguments: [String], at now: Date) -> Choice? {
        guard let index = launchArguments.firstIndex(of: FakeDeparturesProvider.launchArgument) else { return nil }
        guard let name = launchArguments.dropFirst(index + 1).first, !name.hasPrefix("-") else {
            return Choice(scenario: nil, start: now)
        }
        return FakeTrainsScenario(rawValue: name).map { Choice(scenario: $0, start: now) }
    }

    private func load() -> Choice? {
        guard let data = storage.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(Choice.self, from: data)
    }

    private func save(_ choice: Choice?) {
        storage.set(choice.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.key)
    }
}
#endif
