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
    func start(_ content: StationActivityAttributes.ContentState) throws
    func update(_ content: StationActivityAttributes.ContentState) async
    func end() async
}

@MainActor
@Observable
public final class StationLiveActivityModel {
    private struct Inputs {
        let station: Station
        let trains: NextTrainsState
    }

    public private(set) var isShowing: Bool
    public private(set) var startError: StationLiveActivityError?
    public private(set) var content: StationActivityAttributes.ContentState?

    private let client: any StationLiveActivityClient
    private let now: @Sendable () -> Date
    private var inputs: Inputs?
    private var firstLineIndex: Int
    @ObservationIgnored private var lastSystemCall: Task<Void, Never>?

    public init(client: any StationLiveActivityClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
        self.isShowing = client.isShowing
        self.firstLineIndex = client.shownContent?.trains.linesPage?.firstIndex ?? 0
    }

    public func start(station: Station, trains: NextTrainsState) async {
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
        inputs = Inputs(station: station, trains: trains)
        self.content = content
    }

    public func update(station: Station, trains: NextTrainsState) async {
        guard isShowing else { return }
        if switchesStation(to: station) {
            firstLineIndex = 0
        }
        let content = makeContent(station: station, trains: trains)
        inputs = Inputs(station: station, trains: trains)
        self.content = content
        await send(content)
    }

    public func showNextLines() async {
        guard isShowing, let page = (content ?? client.shownContent)?.trains.linesPage else { return }
        firstLineIndex = page.nextFirstIndex
        guard let inputs else { return }
        await update(station: inputs.station, trains: inputs.trains)
    }

    public func stop() async {
        await inOrder { [client] in await client.end() }
        isShowing = false
        content = nil
        inputs = nil
        firstLineIndex = 0
    }

    public func syncWithSystem() {
        isShowing = client.isShowing
        if !isShowing {
            content = nil
            inputs = nil
            firstLineIndex = 0
        }
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
