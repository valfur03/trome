import Foundation
import Observation

public enum NextTrainsState: Equatable, Sendable {
    case idle
    case missingKey
    case loading
    case departures(DepartureBoard, updatedAt: Date)
    case noLiveData
    case failed(NextTrainsError)

    var serverRetryAt: Date? {
        guard case .failed(let error) = self else { return nil }
        return error.serverRetryAt
    }

    func refreshDelay(normally interval: Duration, now: Date) -> Duration {
        guard let serverRetryAt, serverRetryAt > now else { return interval }
        return .seconds(serverRetryAt.timeIntervalSince(now).rounded(.up))
    }
}

extension NextTrainsError {
    var serverRetryAt: Date? {
        guard case .serverOut(let retryAt) = self else { return nil }
        return retryAt
    }
}

/// The next trains of one station, as the last call gave them; `keepUpdated(for:)` asks again every 30 seconds.
///
/// The app makes two of them: one for the next trains screen of the Testing tools, one for the Live Activity.
/// `updatingStationId` says which station the screen keeps up to date, so that the Live Activity
/// takes the trains of the screen and does not ask for the trains of the same station twice.
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
                try await sleep(state(for: station).refreshDelay(normally: refreshInterval, now: now()))
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
        let result: Result<DeparturesAnswer, NextTrainsError>
        do {
            result = .success(try await provider.departuresAnswer(at: stations))
        } catch let error as NextTrainsError {
            result = .failure(error)
        } catch {
            result = .failure(.serviceFailure)
        }
        guard !Task.isCancelled, shownStationId == station.id else { return }
        switch result {
        case .success(let answer):
            let currentTime = now()
            let answeredAt = min(answer.answeredAt ?? currentTime, currentTime)
            let board = DepartureBoard(departures: answer.departures, stations: stations, now: answeredAt)
            state = board.isEmpty ? .noLiveData : .departures(board, updatedAt: answeredAt)
        case .failure(let error):
            state = .failed(error)
        }
    }
}
