import Foundation
import Observation

public struct AutomaticModeStore {
    public static let key = "autoLiveActivity.mode"

    private let storage: any KeyValueStore

    public init(storage: any KeyValueStore) {
        self.storage = storage
    }

    func load() -> AutomaticMode {
        guard let data = storage.data(forKey: Self.key),
              let mode = try? JSONDecoder().decode(AutomaticMode.self, from: data) else {
            return .turnedOn
        }
        return mode
    }

    func save(_ mode: AutomaticMode) {
        storage.set(try? JSONEncoder().encode(mode), forKey: Self.key)
    }
}

@MainActor
@Observable
public final class AutomaticModeModel {
    public private(set) var mode: AutomaticMode {
        didSet { modeDidChange(from: oldValue) }
    }

    private let store: AutomaticModeStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let calendar: Calendar
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public init(
        store: AutomaticModeStore,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.now = now
        self.sleep = sleep
        self.calendar = calendar
        mode = store.load().current(at: now())
        store.save(mode)
        scheduleExpiry()
    }

    deinit {
        expiryTask?.cancel()
    }

    public var allowsAutomaticStart: Bool {
        mode.current(at: now()).allowsAutomaticStart
    }

    public func setOn(_ isOn: Bool) {
        mode = isOn ? .turnedOn : .turnedOff
    }

    func cancelSnooze() {
        guard case .snoozed = mode else { return }
        mode = .turnedOn
    }

    func snooze(for duration: SnoozeDuration) {
        mode = mode.snoozed(for: duration, now: now(), calendar: calendar)
    }

    private func modeDidChange(from oldValue: AutomaticMode) {
        guard mode != oldValue else { return }
        store.save(mode)
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard case .snoozed(let end) = mode else { return }
        let remaining = max(0, end.timeIntervalSince(now()))
        expiryTask = Task { [weak self, sleep] in
            do {
                try await sleep(.seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            let current = self.mode.current(at: self.now())
            if current == self.mode {
                self.scheduleExpiry()
            } else {
                self.mode = current
            }
        }
    }
}
