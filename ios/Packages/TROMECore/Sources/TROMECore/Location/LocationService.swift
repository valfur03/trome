import Foundation
import Observation

/// The one source of the phone's position for every feature of the app.
///
/// Read the position here, never from Core Location: then the fake position of the Testing tools
/// (a `LocationSource.fake`, saved by `LocationSourceStore`) reaches every feature, also the ones added later.
/// Release builds give no `LocationSourceStore`, so they always use the real position.
///
/// The position stream runs only while at least one `PositionNeed` holds: each new position costs battery,
/// and iOS runs the app for it, also in the background. A need that ends stops the stream once no other holds.
@MainActor
@Observable
public final class LocationService {
    public private(set) var source: LocationSource
    private(set) var fix: PositionFix?
    /// Where `fix` came from, when it is a position of the real GPS that the service follows; nil otherwise.
    @ObservationIgnored private(set) var fixOrigin: PositionOrigin?
    /// When the last position of the stream was taken: the keeper often gives the same position first, so only this
    /// tells whether iOS still sends the stream.
    @ObservationIgnored private var lastStreamFixTime: Date?
    public private(set) var problem: LocationProblem?

    public var position: Coordinate? {
        fix?.coordinate
    }

    public var allowsFakePosition: Bool {
        sourceStore != nil
    }

    private let realProvider: any LocationProvider
    private let sourceStore: LocationSourceStore?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private(set) var needs: Set<PositionNeed> = []
    @ObservationIgnored private(set) var isOnScreen = true
    #if DEBUG
    /// The E2E tests keep the app awake in the background in place of the wake for the area of a station, which the
    /// Simulator cannot watch: the screen then keeps following the position off screen, so that a moved position
    /// reaches the arrival rules, as a wake would.
    @ObservationIgnored public var keepsFollowingOffScreen = false
    #endif

    public init(realProvider: any LocationProvider, sourceStore: LocationSourceStore?) {
        self.realProvider = realProvider
        self.sourceStore = sourceStore
        self.source = sourceStore?.load() ?? .realGPS
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Follows the position for `need`, until `stop(for:)` ends that need.
    public func start(for need: PositionNeed = .screen) {
        guard need != .screen || followsTheScreen else { return }
        needs.insert(need)
        guard updatesTask == nil else {
            return
        }
        listen(to: provider(for: source))
    }

    /// Ends `need`, and stops the position stream when no other need holds. The last position stays.
    public func stop(for need: PositionNeed) {
        needs.remove(need)
        guard needs.isEmpty else { return }
        stopListening()
    }

    /// Off screen, the need of the screen ends, and a start for it that comes late (after a permission question) is
    /// ignored: the screen follows the position again when the app is back on screen.
    public func setOnScreen(_ onScreen: Bool) {
        isOnScreen = onScreen
        if !followsTheScreen {
            stop(for: .screen)
        }
    }

    private var followsTheScreen: Bool {
        #if DEBUG
        isOnScreen || keepsFollowingOffScreen
        #else
        isOnScreen
        #endif
    }

    /// Ends every need at once.
    public func stop() {
        needs.removeAll()
        stopListening()
    }

    private func stopListening() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    public func use(_ newSource: LocationSource) {
        guard let sourceStore else {
            return
        }
        source = newSource
        sourceStore.save(newSource)
        fixOrigin = nil
        lastStreamFixTime = nil
        fix = nil
        problem = nil
        if updatesTask != nil {
            stopListening()
            listen(to: provider(for: newSource))
        }
    }

    /// A position of the updates that keep the app running in the background (`BackgroundLocationKeeper`).
    /// Taken only while the service follows the real GPS, and only when it is newer than the last position:
    /// the stream and these updates often give the same position, and it counts once.
    public func takeBackgroundFix(_ newFix: PositionFix) {
        guard updatesTask != nil, source == .realGPS else { return }
        if let fix, newFix.timestamp <= fix.timestamp { return }
        handle(.position(newFix), from: .keeper(lastStreamFix: lastStreamFixTime))
    }

    func requestCurrentFix() async -> PositionFix? {
        let requestedSource = source
        guard let newFix = await provider(for: requestedSource).currentFix(), source == requestedSource else {
            return nil
        }
        fixOrigin = nil
        fix = newFix
        problem = nil
        return newFix
    }

    private func provider(for source: LocationSource) -> any LocationProvider {
        switch source {
        case .realGPS:
            realProvider
        case .fake(let fakePosition):
            FakeLocationProvider(coordinate: fakePosition.coordinate)
        }
    }

    private func listen(to provider: any LocationProvider) {
        let events = provider.events()
        updatesTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                self?.handle(event)
            }
            if !Task.isCancelled {
                self?.updatesTask = nil
            }
        }
    }

    private func handle(_ event: LocationEvent, from origin: PositionOrigin = .stream) {
        switch event {
        case .position(let newFix):
            fixOrigin = source == .realGPS ? origin : nil
            if fixOrigin == .stream {
                lastStreamFixTime = newFix.timestamp
            }
            fix = newFix
            problem = nil
        case .problem(let newProblem):
            if newProblem == .permissionDenied {
                fix = nil
            }
            problem = newProblem
        }
    }
}

/// Where a position of the real GPS came from, for the wake log: a walk then tells which one moved the Live Activity.
public enum PositionOrigin: Equatable, Sendable {
    /// The position stream of the provider, which iOS stops about 10 seconds after the app leaves the screen,
    /// unless the app still counts as in use.
    case stream
    /// The updates of `BackgroundLocationKeeper`, which go on in the background while a Live Activity shows.
    /// Both sources often give the same position, and either can come first, so the keeper's position carries when
    /// the stream gave its last one: that age, not the source, tells whether iOS stopped the stream.
    case keeper(lastStreamFix: Date?)
}

/// Why the app follows the position.
public enum PositionNeed: Hashable, Sendable {
    /// The app is on screen: the main screen shows the nearest station.
    case screen
    /// Work in the background: a Live Activity shows (to switch or end it),
    /// or the app decides an arrival that iOS reported for the area of a station.
    case backgroundWork
}
