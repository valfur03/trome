import Foundation

public struct RegionFirstStates: Sendable {
    public enum State: Sendable {
        case inside
        case outside
        case unknown
        case notWatched
    }

    private var pending: Set<String>
    private var outsideCount = 0
    private var insideLabels: [String] = []
    private var problemCounts: [String: Int] = [:]

    public init(expecting ids: Set<String> = []) {
        pending = ids
    }

    public var isComplete: Bool {
        pending.isEmpty
    }

    /// Takes a first state that gets its own line, out of the summary.
    public mutating func release(id: String) -> Bool {
        pending.remove(id) != nil
    }

    public mutating func take(id: String, label: String, state: State, problems: String) -> Bool {
        guard pending.remove(id) != nil else { return false }
        switch (state, problems.isEmpty) {
        case (.outside, true):
            outsideCount += 1
        case (.inside, true):
            insideLabels.append(label)
        default:
            let word = switch state {
            case .inside: "inside"
            case .outside: "outside"
            case .unknown: "unknown"
            case .notWatched: "not watched"
            }
            let key = problems.isEmpty ? word : "\(word) [\(problems)]"
            problemCounts[key, default: 0] += 1
        }
        return true
    }

    public var summary: String? {
        let count = outsideCount + insideLabels.count + problemCounts.values.reduce(0, +)
        guard count > 0 else { return nil }
        var parts: [String] = []
        if outsideCount > 0 {
            parts.append("\(outsideCount) outside")
        }
        if !insideLabels.isEmpty {
            parts.append("inside \(insideLabels.joined(separator: ", "))")
        }
        parts += problemCounts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        return "iOS: first state of \(count) new areas: \(parts.joined(separator: ", "))"
    }
}
