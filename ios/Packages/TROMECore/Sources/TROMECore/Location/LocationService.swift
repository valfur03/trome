import Observation

@MainActor
@Observable
public final class LocationService {
    public private(set) var source: LocationSource
    private(set) var fix: PositionFix?
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

    public init(realProvider: any LocationProvider, sourceStore: LocationSourceStore?) {
        self.realProvider = realProvider
        self.sourceStore = sourceStore
        self.source = sourceStore?.load() ?? .realGPS
    }

    deinit {
        updatesTask?.cancel()
    }

    public func start() {
        guard updatesTask == nil else {
            return
        }
        listen(to: provider(for: source))
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    public func use(_ newSource: LocationSource) {
        guard let sourceStore else {
            return
        }
        source = newSource
        sourceStore.save(newSource)
        fix = nil
        problem = nil
        if updatesTask != nil {
            stop()
            listen(to: provider(for: newSource))
        }
    }

    func requestCurrentFix() async -> PositionFix? {
        let requestedSource = source
        guard let newFix = await provider(for: requestedSource).currentFix(), source == requestedSource else {
            return nil
        }
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

    private func handle(_ event: LocationEvent) {
        switch event {
        case .position(let newFix):
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
