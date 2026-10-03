import Foundation
import Observation

public enum StationLiveActivityError: Error, Equatable, Sendable {
    case turnedOff
    case failed
}

@MainActor
public protocol StationLiveActivityClient: AnyObject {
    var isShowing: Bool { get }
    var shownContent: StationActivityAttributes.ContentState? { get }
    var areActivitiesEnabled: Bool { get }
    func start(_ content: StationActivityAttributes.ContentState) throws
    func update(_ content: StationActivityAttributes.ContentState) async
    func end() async
}

@MainActor
@Observable
public final class StationLiveActivityModel {
    public private(set) var isShowing: Bool
    public private(set) var startError: StationLiveActivityError?
    public private(set) var content: StationActivityAttributes.ContentState?

    private let client: any StationLiveActivityClient
    private let store: StationLiveActivityInputsStore?
    private let now: @Sendable () -> Date
    private var inputs: StationLiveActivityInputs?
    private var firstLineIndex: Int
    private var keptTimesStaleDate: Date?
    @ObservationIgnored private var lastSystemCall: Task<Void, Never>?

    public init(
        client: any StationLiveActivityClient,
        store: StationLiveActivityInputsStore? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.store = store
        self.now = now
        self.isShowing = client.isShowing
        let shown = client.shownContent
        self.firstLineIndex = shown?.trains.linesPage?.firstIndex ?? 0
        if client.isShowing, let shown, shown.trains.linesPage != nil,
           let saved = store?.load(), saved.station.name == shown.stationName {
            inputs = saved
            keptTimesStaleDate = shown.staleDate
        }
    }

    public func start(station: Station, trains: NextTrainsState) async {
        if client.isShowing, keepShownTimesIfFailed(trains, at: station) {
            startError = nil
            isShowing = true
            return
        }
        if !client.isShowing || switchesStation(to: station) {
            firstLineIndex = 0
        }
        let content = makeContent(station: station, trains: trains)
        if client.isShowing {
            await send(content)
        } else {
            do {
                try client.start(content)
            } catch let error as StationLiveActivityError {
                startError = error
                return
            } catch {
                startError = .failed
                return
            }
        }
        startError = nil
        isShowing = true
        keptTimesStaleDate = nil
        remember(StationLiveActivityInputs(station: station, trains: trains))
        self.content = content
    }

    public func update(station: Station, trains: NextTrainsState) async {
        guard isShowing, !keepShownTimesIfFailed(trains, at: station) else { return }
        keptTimesStaleDate = nil
        await show(station: station, trains: trains)
    }

    public func showNextLines() async {
        guard isShowing, let shown = content ?? client.shownContent, let page = shown.trains.linesPage else { return }
        firstLineIndex = page.nextFirstIndex
        guard let inputs, !keptTimesAreStale(at: now()) else {
            await send(shown)
            return
        }
        await show(station: inputs.station, trains: inputs.trains)
    }

    func redraw() async {
        guard isShowing, let inputs, !keptTimesAreStale(at: now()) else { return }
        await show(station: inputs.station, trains: inputs.trains)
    }

    func nextRedrawDate(after now: Date) -> Date? {
        guard let content, let date = content.trains.linesPage?.nextRedrawDate(after: content.updatedAt) else {
            return nil
        }
        let due = max(date, now)
        return keptTimesAreStale(at: due) ? nil : due
    }

    public func stop() async {
        await inOrder { [client] in await client.end() }
        isShowing = false
        forgetShownContent()
    }

    public func syncWithSystem() {
        isShowing = client.isShowing
        if startError == .turnedOff, client.areActivitiesEnabled {
            startError = nil
        }
        if !isShowing {
            forgetShownContent()
        }
    }

    private func forgetShownContent() {
        content = nil
        remember(nil)
        firstLineIndex = 0
        keptTimesStaleDate = nil
    }

    private func show(station: Station, trains: NextTrainsState) async {
        if switchesStation(to: station) {
            firstLineIndex = 0
        }
        let content = makeContent(station: station, trains: trains)
        remember(StationLiveActivityInputs(station: station, trains: trains))
        self.content = content
        await send(content)
    }

    private func remember(_ newInputs: StationLiveActivityInputs?) {
        guard newInputs != inputs else { return }
        inputs = newInputs
        store?.save(newInputs)
    }

    private func keepShownTimesIfFailed(_ trains: NextTrainsState, at station: Station) -> Bool {
        guard case .failed = trains, let staleDate = shownTimesStaleDate(of: station) else { return false }
        keptTimesStaleDate = keptTimesStaleDate ?? staleDate
        return true
    }

    private func shownTimesStaleDate(of station: Station) -> Date? {
        let showsStation = inputs.map { $0.station.id == station.id }
            ?? (client.shownContent?.stationName == station.name)
        guard showsStation, let shown = content ?? client.shownContent, shown.trains.linesPage != nil else {
            return nil
        }
        return shown.staleDate
    }

    private func keptTimesAreStale(at date: Date) -> Bool {
        keptTimesStaleDate.map { date >= $0 } ?? false
    }

    private func send(_ content: StationActivityAttributes.ContentState) async {
        await inOrder { [client] in await client.update(content) }
    }

    private func inOrder(_ call: @escaping @MainActor () async -> Void) async {
        let previous = lastSystemCall
        let next = Task {
            await previous?.value
            await call()
        }
        lastSystemCall = next
        await next.value
    }

    private func switchesStation(to station: Station) -> Bool {
        inputs.map { $0.station.id != station.id } ?? false
    }

    private func makeContent(station: Station, trains: NextTrainsState) -> StationActivityAttributes.ContentState {
        StationActivityAttributes.ContentState(
            station: station,
            trains: trains,
            now: now(),
            firstLineIndex: firstLineIndex
        )
    }
}
