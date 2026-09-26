import Foundation
import Observation

public enum StationLiveActivityError: Error, Equatable, Sendable {
    case turnedOff
    case failed
}

@MainActor
public protocol StationLiveActivityClient: AnyObject {
    var isShowing: Bool { get }
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
    private let now: @Sendable () -> Date

    public init(client: any StationLiveActivityClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
        self.isShowing = client.isShowing
    }

    public func start(station: Station, trains: NextTrainsState) async {
        let content = StationActivityAttributes.ContentState(station: station, trains: trains, now: now())
        if client.isShowing {
            await client.update(content)
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
        self.content = content
    }

    public func update(station: Station, trains: NextTrainsState) async {
        guard isShowing else { return }
        let content = StationActivityAttributes.ContentState(station: station, trains: trains, now: now())
        self.content = content
        await client.update(content)
    }

    public func stop() async {
        await client.end()
        isShowing = false
        content = nil
    }

    public func syncWithSystem() {
        isShowing = client.isShowing
        if !isShowing {
            content = nil
        }
    }
}
