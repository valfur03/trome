import Foundation
import Synchronization
import Testing
@testable import RATPCore

final class StubDeparturesProvider: DeparturesProvider {
    private let results = Mutex<[String: Result<[Departure], NextTrainsError>]>([:])
    private let calls = Mutex(0)

    var callCount: Int {
        calls.withLock { $0 }
    }

    private let askedStations = Mutex<[[String]]>([])

    var askedStationIds: [[String]] {
        askedStations.withLock { $0 }
    }

    func answer(_ result: Result<[Departure], NextTrainsError>, for station: Station) {
        results.withLock { $0[station.id] = result }
    }

    func departures(at stations: [Station]) async throws -> [Departure] {
        calls.withLock { $0 += 1 }
        askedStations.withLock { $0.append(stations.map(\.id)) }
        return try results.withLock { $0[stations[0].id] ?? .success([]) }.get()
    }
}

@MainActor
struct NextTrainsModelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line12 = TransitLine(mode: .metro, name: "12")
    private let provider = StubDeparturesProvider()
    private var abbesses: Station {
        Station(id: "abbesses", name: "Abbesses", coordinate: Coordinate(48.8844, 2.3384), lines: [line12])
    }
    private var pigalle: Station {
        Station(id: "pigalle", name: "Pigalle", coordinate: Coordinate(48.8822, 2.3377), lines: [line12])
    }

    private func makeModel(sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }) -> NextTrainsModel {
        NextTrainsModel(provider: provider, now: { [now] in now }, sleep: sleep)
    }

    private func departure(inMinutes minutes: Double) -> Departure {
        Departure(line: line12, destination: "Mairie d'Issy", time: now.addingTimeInterval(minutes * 60))
    }

    @Test func saysTheKeyIsMissingWithoutAProvider() async {
        let model = NextTrainsModel(provider: nil)

        await model.refresh(for: abbesses)

        #expect(model.state == .missingKey)
    }

    @Test func showsTheNextTrainsOfTheStation() async {
        provider.answer(.success([departure(inMinutes: 2)]), for: abbesses)
        let model = makeModel()

        await model.refresh(for: abbesses)

        let board = DepartureBoard(departures: [departure(inMinutes: 2)], stations: [abbesses], now: now)
        #expect(model.state == .departures(board, updatedAt: now))
    }

    @Test func showsTheTrainsOfEveryStationOfTheHubOfTheStation() async {
        let rerB = TransitLine(mode: .rer, name: "B")
        var metro = abbesses
        metro.hubId = "hub"
        let rer = Station(id: "rer", name: "RER", coordinate: Coordinate(48.8845, 2.3385), lines: [rerB], hubId: "hub")
        let rerTrain = Departure(line: rerB, destination: "Robinson", time: now.addingTimeInterval(60))
        provider.answer(.success([departure(inMinutes: 2), rerTrain]), for: metro)
        let model = NextTrainsModel(
            provider: provider,
            catalog: StationCatalog(stations: [metro, rer, pigalle]),
            now: { [now] in now }
        )

        await model.refresh(for: metro)

        #expect(provider.askedStationIds == [["abbesses", "rer"]])
        let board = DepartureBoard(departures: [departure(inMinutes: 2), rerTrain], stations: [metro, rer], now: now)
        #expect(model.state == .departures(board, updatedAt: now))
    }

    @Test func saysThereIsNoLiveDataWhenNoTrainIsAnnounced() async {
        provider.answer(.success([]), for: abbesses)
        let model = makeModel()

        await model.refresh(for: abbesses)

        #expect(model.state == .noLiveData)
    }

    @Test(arguments: [NextTrainsError.unreachable, .keyRejected, .quotaExceeded, .serviceFailure])
    func reportsWhyTheTrainsCannotBeShown(error: NextTrainsError) async {
        provider.answer(.failure(error), for: abbesses)
        let model = makeModel()

        await model.refresh(for: abbesses)

        #expect(model.state == .failed(error))
    }

    @Test func showsTheOtherStationTrainsAfterAnotherPick() async {
        provider.answer(.success([departure(inMinutes: 2)]), for: abbesses)
        provider.answer(.success([]), for: pigalle)
        let model = makeModel()

        await model.refresh(for: abbesses)
        await model.refresh(for: pigalle)

        #expect(model.state == .noLiveData)
    }

    @Test func keepsAskingForNewTimesUntilStopped() async {
        let sleeps = Mutex(0)
        let model = makeModel { _ in
            let count = sleeps.withLock { count in
                count += 1
                return count
            }
            if count == 3 {
                throw CancellationError()
            }
        }

        await model.keepUpdated(for: abbesses)

        #expect(provider.callCount == 3)
    }

    @Test func waitsTheRefreshIntervalBetweenTwoUpdates() async {
        let waits = Mutex<[Duration]>([])
        let model = NextTrainsModel(provider: provider, refreshInterval: .seconds(30), sleep: { duration in
            waits.withLock { $0.append(duration) }
            throw CancellationError()
        })

        await model.keepUpdated(for: abbesses)

        #expect(waits.withLock { $0 } == [.seconds(30)])
    }

    @Test func saysWhichStationItKeepsUpdatedUntilItStops() async {
        let model = makeModel(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })

        let updates = Task { await model.keepUpdated(for: abbesses) }
        for _ in 0..<1_000 where provider.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(model.updatingStationId == "abbesses")
        updates.cancel()
        await updates.value

        #expect(model.updatingStationId == nil)
    }

    @Test func givesTheStateOfTheShownStation() async {
        provider.answer(.success([]), for: abbesses)
        let model = makeModel()

        await model.refresh(for: abbesses)

        #expect(model.state(for: abbesses) == .noLiveData)
    }

    @Test func saysAnotherStationIsStillLoading() async {
        provider.answer(.success([]), for: abbesses)
        let model = makeModel()

        await model.refresh(for: abbesses)

        #expect(model.state(for: pigalle) == .loading)
    }

    @Test func saysTheKeyIsMissingForAnyStation() {
        #expect(NextTrainsModel(provider: nil).state(for: pigalle) == .missingKey)
    }
}
