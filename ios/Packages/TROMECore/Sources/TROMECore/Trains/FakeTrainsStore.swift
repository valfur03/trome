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

    /// A launch with arguments comes from a harness (`xcrun simctl launch`, a UI test, an Xcode scheme): it saves its
    /// choice, on or off. A launch with none comes from iOS (a tap on the Live Activity, a region event, a background
    /// relaunch): it keeps the saved choice, so the fake trains survive it.
    public func launch(with launchArguments: [String], at now: Date = Date()) -> FakeTrainsLaunch {
        let saved = load()
        let arguments = Array(launchArguments.dropFirst())
        guard !arguments.isEmpty else {
            return FakeTrainsLaunch(arguments: arguments, saved: saved, used: saved, now: now)
        }
        let choice = Self.choice(askedBy: launchArguments, at: now)
        save(choice)
        return FakeTrainsLaunch(arguments: arguments, saved: saved, used: choice, now: now)
    }

    public func provider(forLaunchWith launchArguments: [String], at now: Date = Date()) -> FakeDeparturesProvider? {
        launch(with: launchArguments, at: now).provider
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
