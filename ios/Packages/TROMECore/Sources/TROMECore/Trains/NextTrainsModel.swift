import Foundation
import Observation

public enum NextTrainsState: Equatable, Sendable {
    case idle
    case missingKey
    case loading
    case departures(DepartureBoard, updatedAt: Date)
    case noLiveData
    case failed(NextTrainsError)
}

@MainActor
@Observable
public final class NextTrainsModel {
    public static let refreshInterval: Duration = .seconds(30)

    public private(set) var state: NextTrainsState = .idle
    public private(set) var updatingStationId: String?

    private let provider: (any DeparturesProvider)?
    private let catalog: StationCatalog?
    private let refreshInterval: Duration
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var shownStationId: String?
    private var updateCount = 0

    public init(
        provider: (any DeparturesProvider)?,
        catalog: StationCatalog? = nil,
        refreshInterval: Duration = NextTrainsModel.refreshInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.provider = provider
        self.catalog = catalog
        self.refreshInterval = refreshInterval
        self.now = now
        self.sleep = sleep
        if provider == nil {
            state = .missingKey
        }
    }

    public func state(for station: Station) -> NextTrainsState {
        provider == nil || shownStationId == station.id ? state : .loading
    }

    public func keepUpdated(for station: Station) async {
        guard provider != nil else { return }
        updateCount += 1
        let update = updateCount
        updatingStationId = station.id
        defer {
            if updateCount == update {
                updatingStationId = nil
            }
        }
        while !Task.isCancelled {
            await refresh(for: station)
            do {
                try await sleep(refreshInterval)
            } catch {
                return
            }
        }
    }

    public func refresh(for station: Station) async {
        guard let provider else {
            state = .missingKey
            return
        }
        if shownStationId != station.id {
            shownStationId = station.id
            state = .loading
        }
        let stations = catalog?.hubStations(of: station) ?? [station]
        let result: Result<[Departure], NextTrainsError>
        do {
            result = .success(try await provider.departures(at: stations))
        } catch let error as NextTrainsError {
            result = .failure(error)
        } catch {
            result = .failure(.serviceFailure)
        }
        guard !Task.isCancelled, shownStationId == station.id else { return }
        switch result {
        case .success(let departures):
            let currentTime = now()
            let board = DepartureBoard(departures: departures, stations: stations, now: currentTime)
            state = board.isEmpty ? .noLiveData : .departures(board, updatedAt: currentTime)
        case .failure(let error):
            state = .failed(error)
        }
    }
}
