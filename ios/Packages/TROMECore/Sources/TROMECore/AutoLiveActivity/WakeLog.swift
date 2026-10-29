import Foundation
import Observation

public struct WakeLogEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case launch
        case system
        case regions
        case decision
        case notification
        case silentStart
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let text: String

    public init(id: UUID = UUID(), date: Date, kind: Kind, text: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
    }
}

@MainActor
@Observable
public final class WakeLog {
    public static let key = "testingTools.wakeLog"
    public static let maximumEntries = 500

    public private(set) var entries: [WakeLogEntry]
    @ObservationIgnored private let storage: any KeyValueStore
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(storage: any KeyValueStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.now = now
        entries = storage.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([WakeLogEntry].self, from: $0) } ?? []
    }

    public func record(_ kind: WakeLogEntry.Kind, _ text: String, unlessRepeated: Bool = false) {
        if unlessRepeated, entries.first(where: { $0.kind == kind })?.text == text {
            return
        }
        entries.insert(WakeLogEntry(date: now(), kind: kind, text: text), at: 0)
        if entries.count > Self.maximumEntries {
            entries.removeLast(entries.count - Self.maximumEntries)
        }
        save()
    }

    public func clear() {
        entries = []
        save()
    }

    private func save() {
        storage.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}
