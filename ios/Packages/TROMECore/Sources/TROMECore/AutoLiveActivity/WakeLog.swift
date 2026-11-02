import Foundation
import Observation

public struct WakeLogEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case launch
        case system
        case regions
        case decision
        /// Written only by earlier builds, which sent the arrival notification: kept so that their lines still read.
        case notification
        case silentStart
        case trains
        /// A group of PRIM entries of `PRIMWalkRecord`.
        case prim
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
    /// When this process made the log: its launch, as the composition root makes the log at once.
    /// The lines of a wake and of the start token count their seconds from it.
    public let launchedAt: Date
    @ObservationIgnored private let storage: any KeyValueStore
    @ObservationIgnored let now: @Sendable () -> Date

    public init(storage: any KeyValueStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.now = now
        launchedAt = now()
        entries = storage.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([WakeLogEntry].self, from: $0) } ?? []
    }

    /// Writes a line, and keeps the 500 newest; with `keepingAtMost`, also only that many newest lines of its kind
    /// that `alike` matches, so that the other lines of the kind keep their place.
    public func record(
        _ kind: WakeLogEntry.Kind,
        _ text: String,
        unlessRepeated: Bool = false,
        keepingAtMost kindLimit: Int? = nil,
        alike: (WakeLogEntry) -> Bool = { _ in true }
    ) {
        if unlessRepeated, entries.first(where: { $0.kind == kind })?.text == text {
            return
        }
        entries.insert(WakeLogEntry(date: now(), kind: kind, text: text), at: 0)
        if let kindLimit {
            let older = Set(entries.filter { $0.kind == kind && alike($0) }.dropFirst(kindLimit).map(\.id))
            entries.removeAll { older.contains($0.id) }
        }
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
