import Foundation
import Observation
#if DEBUG
import os

private let pagerLogger = Logger(category: "LiveActivity")
#endif

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
    public private(set) var areActivitiesEnabled: Bool
    public private(set) var content: StationActivityAttributes.ContentState?
    public private(set) var serverRetryAt: Date?

    private let client: any StationLiveActivityClient
    private let store: StationLiveActivityInputsStore?
    private let now: @Sendable () -> Date
    private var inputs: StationLiveActivityInputs?
    private var firstLineIndex: Int
    private var keptTimesStaleDate: Date?
    @ObservationIgnored private var lastSystemCall: Task<Void, Never>?
    @ObservationIgnored private var startCount = 0

    public init(
        client: any StationLiveActivityClient,
        store: StationLiveActivityInputsStore? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.store = store
        self.now = now
        self.isShowing = client.isShowing
        self.areActivitiesEnabled = client.areActivitiesEnabled
        let shown = client.shownContent
        self.firstLineIndex = shown?.trains.linesPage?.firstIndex ?? 0
        if client.isShowing, let shown, shown.trains.linesPage != nil,
           let saved = store?.load(), saved.station.name == shown.stationName {
            inputs = saved
            keptTimesStaleDate = shown.staleDate
        }
    }

    public func start(station: Station, trains: NextTrainsState) async {
        await waitForTheSystemCallsInProgress()
        if client.isShowing, keepShownTimesIfFailed(trains, at: station) {
            startError = nil
            isShowing = true
            await sayWhetherTheServerIsOut(trains)
            return
        }
        if !client.isShowing || switchesStation(to: station) {
            firstLineIndex = 0
        }
        let content = makeContent(station: station, trains: trains, serverIsOut: trains.serverRetryAt != nil)
        if client.isShowing {
            await send(content)
        } else {
            do {
                try client.start(content)
            } catch let error as StationLiveActivityError {
                startError = error
                areActivitiesEnabled = client.areActivitiesEnabled
                return
            } catch {
                startError = .failed
                return
            }
        }
        startError = nil
        isShowing = true
        startCount += 1
        keptTimesStaleDate = nil
        serverRetryAt = trains.serverRetryAt
        remember(StationLiveActivityInputs(station: station, trains: trains))
        self.content = content
    }

    public func update(station: Station, trains: NextTrainsState) async {
        guard isShowing else { return }
        guard !keepShownTimesIfFailed(trains, at: station) else {
            await sayWhetherTheServerIsOut(trains)
            return
        }
        keptTimesStaleDate = nil
        serverRetryAt = trains.serverRetryAt
        await show(station: station, trains: trains)
    }

    public func showNextLines() async {
        guard isShowing, let shown = content ?? client.shownContent, let page = shown.trains.linesPage else {
            Self.logPager("show the next lines: no page shown (showing: \(isShowing))")
            return
        }
        firstLineIndex = page.nextFirstIndex
        Self.logPager("show the next lines of \(shown.stationName): page from \(page.firstIndex) to \(firstLineIndex)")
        guard let inputs, !keptTimesAreStale(at: now()) else {
            let kept = markedStaleIfTheKeptTimesAreOld(shown)
            if kept != shown {
                content = kept
            }
            await send(kept)
            return
        }
        await show(station: inputs.station, trains: inputs.trains)
    }

    func redraw() async {
        guard isShowing else { return }
        guard !keptTimesAreStale(at: now()) else {
            await markTheKeptTimesStaleOnceTheyAreOld()
            return
        }
        guard let inputs else { return }
        await show(station: inputs.station, trains: inputs.trains)
    }

    /// The next time a running app draws the Live Activity again: when a train of the page changes its
    /// status, or, for kept times, when they get old, to mark them stale (iOS would wait up to 2 minutes).
    /// With no trains to draw the page from, only the mark is planned: a date that `redraw()` cannot act on
    /// would come back at once, and the background loop would never sleep.
    func nextRedrawDate(after now: Date) -> Date? {
        guard let content, !content.isMarkedStale else { return nil }
        let pageDate = inputs == nil
            ? nil
            : content.trains.linesPage?.nextRedrawDate(after: content.updatedAt).map { max($0, now) }
        guard let keptTimesStaleDate else { return pageDate }
        let markDate = max(keptTimesStaleDate, now)
        return pageDate.map { min($0, markDate) } ?? markDate
    }

    public func stop() async {
        isShowing = false
        forgetShownContent()
        let startsBeforeTheEnd = startCount
        await inOrder { [client] in await client.end() }
        if startCount == startsBeforeTheEnd {
            isShowing = false
        }
    }

    public func syncWithSystem() {
        isShowing = client.isShowing
        areActivitiesEnabled = client.areActivitiesEnabled
        if startError == .turnedOff, areActivitiesEnabled {
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
        serverRetryAt = nil
    }

    private func sayWhetherTheServerIsOut(_ trains: NextTrainsState) async {
        serverRetryAt = trains.serverRetryAt
        guard let shown = content ?? client.shownContent else { return }
        var kept = markedStaleIfTheKeptTimesAreOld(shown)
        kept.serverIsOut = serverRetryAt != nil
        await sendIfChanged(kept, from: shown)
    }

    private func markTheKeptTimesStaleOnceTheyAreOld() async {
        guard let shown = content ?? client.shownContent else { return }
        await sendIfChanged(markedStaleIfTheKeptTimesAreOld(shown), from: shown)
    }

    private func sendIfChanged(
        _ kept: StationActivityAttributes.ContentState,
        from shown: StationActivityAttributes.ContentState
    ) async {
        guard kept != shown else { return }
        content = kept
        await send(kept)
    }

    private func markedStaleIfTheKeptTimesAreOld(
        _ shown: StationActivityAttributes.ContentState
    ) -> StationActivityAttributes.ContentState {
        guard keptTimesAreStale(at: now()) else { return shown }
        var marked = shown
        marked.isMarkedStale = true
        return marked
    }

    private func show(station: Station, trains: NextTrainsState) async {
        if switchesStation(to: station) {
            firstLineIndex = 0
        }
        let content = makeContent(station: station, trains: trains, serverIsOut: serverRetryAt != nil)
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

    private func waitForTheSystemCallsInProgress() async {
        while let pending = lastSystemCall {
            await pending.value
            if lastSystemCall == pending {
                lastSystemCall = nil
            }
        }
    }

    private func inOrder(_ call: @escaping @MainActor () async -> Void) async {
        let previous = lastSystemCall
        let next = Task {
            await previous?.value
            await call()
        }
        lastSystemCall = next
        await next.value
        if lastSystemCall == next {
            lastSystemCall = nil
        }
    }

    private static func logPager(_ event: String) {
        #if DEBUG
        pagerLogger.notice("\(event, privacy: .public)")
        #endif
    }

    private func switchesStation(to station: Station) -> Bool {
        inputs.map { $0.station.id != station.id } ?? false
    }

    private func makeContent(
        station: Station,
        trains: NextTrainsState,
        serverIsOut: Bool
    ) -> StationActivityAttributes.ContentState {
        StationActivityAttributes.ContentState(
            station: station,
            trains: trains,
            now: now(),
            firstLineIndex: firstLineIndex,
            serverIsOut: serverIsOut
        )
    }
}
