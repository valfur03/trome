import Observation

@MainActor
@Observable
public final class LocationService {
    public private(set) var source: LocationSource
    public private(set) var position: Coordinate?

    public var allowsFakePosition: Bool {
        sourceStore != nil
    }

    private let realProvider: any LocationProvider
    private let sourceStore: LocationSourceStore?
    private var updatesTask: Task<Void, Never>?

    public init(realProvider: any LocationProvider, sourceStore: LocationSourceStore?) {
        self.realProvider = realProvider
        self.sourceStore = sourceStore
        self.source = sourceStore?.load() ?? .realGPS
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
        position = nil
        if updatesTask != nil {
            stop()
            listen(to: provider(for: newSource))
        }
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
        let positions = provider.positions()
        updatesTask = Task { [weak self] in
            for await coordinate in positions {
                guard !Task.isCancelled else {
                    return
                }
                self?.position = coordinate
            }
        }
    }
}
