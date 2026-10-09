#if DEBUG
import Foundation

/// What one launch did with the fake trains, and its line of the log, so that a "no data" screen can be told apart
/// from a launch that lost its arguments.
public struct FakeTrainsLaunch {
    let arguments: [String]
    let saved: FakeTrainsStore.Choice?
    let used: FakeTrainsStore.Choice?
    let now: Date

    public var provider: FakeDeparturesProvider? {
        used.map { FakeDeparturesProvider(scenario: $0.scenario, start: $0.start) }
    }

    /// One line, with no secret: only the fake-trains argument is written, never the other arguments.
    /// `ios/scripts/fake-trains.sh` reads it: keep `(unknown state)` and `uses: fake trains <state> from` as they are.
    public func logLine(hasTrainDataKey: Bool, timeZone: TimeZone = .current) -> String {
        let time = Date.ISO8601FormatStyle(timeZone: timeZone).time(includingFractionalSeconds: false)
        let noFakeTrains = "no fake trains, " + (hasTrainDataKey ? "live trains of the key" : "no key: no data")
        return [
            "launch \(launchedBy)",
            "saved: \(saved.map { describe($0, time) } ?? "no fake trains")",
            "uses: \(used.map { describe($0, time) } ?? noFakeTrains)"
        ].joined(separator: " | ")
    }

    private var launchedBy: String {
        guard !arguments.isEmpty else { return "by iOS, no argument" }
        guard let index = arguments.firstIndex(of: FakeDeparturesProvider.launchArgument) else {
            return "by the harness, no \(FakeDeparturesProvider.launchArgument)"
        }
        guard let name = arguments.dropFirst(index + 1).first, !name.hasPrefix("-") else {
            return "by the harness, \(FakeDeparturesProvider.launchArgument)"
        }
        let known = FakeTrainsScenario(rawValue: name) != nil
        return "by the harness, \(FakeDeparturesProvider.launchArgument) \(name)\(known ? "" : " (unknown state)")"
    }

    private func describe(_ choice: FakeTrainsStore.Choice, _ time: Date.ISO8601FormatStyle) -> String {
        "fake trains \(choice.scenario?.rawValue ?? "default") from \(choice.start.formatted(time))"
    }
}
#endif
