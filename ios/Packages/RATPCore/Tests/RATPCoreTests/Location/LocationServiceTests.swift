import Foundation
import Testing
@testable import RATPCore

final class ControlledLocationProvider: LocationProvider, @unchecked Sendable {
    private var continuation: AsyncStream<LocationEvent>.Continuation?
    private(set) var isReporting = false

    func events() -> AsyncStream<LocationEvent> {
        let (stream, continuation) = AsyncStream<LocationEvent>.makeStream()
        continuation.onTermination = { [weak self] _ in
            self?.isReporting = false
        }
        self.continuation = continuation
        isReporting = true
        return stream
    }

    func report(_ coordinate: Coordinate) {
        report(.exact(coordinate))
    }

    func report(_ fix: PositionFix) {
        continuation?.yield(.position(fix))
    }

    func report(_ problem: LocationProblem) {
        continuation?.yield(.problem(problem))
    }

    func stopReporting() {
        continuation?.finish()
    }
}

@MainActor
struct LocationServiceTests {
    private let gps = ControlledLocationProvider()
    private let storage = InMemoryKeyValueStore()
    private let realPosition = Coordinate(48.8584, 2.2945)
    private let chatelet = FakePosition(name: "Châtelet", coordinate: Coordinate(48.85855, 2.34743))

    private func makeService(allowsFakePosition: Bool = true) -> LocationService {
        LocationService(
            realProvider: gps,
            sourceStore: allowsFakePosition ? LocationSourceStore(storage: storage) : nil
        )
    }

    private func waitForProblem(_ expected: LocationProblem?, in service: LocationService) async {
        for _ in 0..<1_000 where service.problem != expected {
            await Task.yield()
        }
    }

    private func waitForPosition(_ expected: Coordinate?, in service: LocationService) async {
        for _ in 0..<1_000 where service.position != expected {
            await Task.yield()
        }
    }

    @Test func reportsTheRealGPSPositionByDefault() async {
        let service = makeService()
        service.start()
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)

        #expect(service.source == .realGPS)
        #expect(service.position == realPosition)
    }

    @Test func reportsTheFakePositionOnceChosen() async {
        let service = makeService()
        service.start()
        service.use(.fake(chatelet))
        gps.report(realPosition)
        await waitForPosition(chatelet.coordinate, in: service)

        #expect(service.source == .fake(chatelet))
        #expect(service.position == chatelet.coordinate)
    }

    @Test func goesBackToTheRealGPSPosition() async {
        let service = makeService()
        service.start()
        service.use(.fake(chatelet))
        await waitForPosition(chatelet.coordinate, in: service)
        service.use(.realGPS)
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)

        #expect(service.position == realPosition)
    }

    @Test func restartsTheRealGPSAfterItStopped() async {
        let service = makeService()
        service.start()
        gps.stopReporting()
        for _ in 0..<1_000 {
            await Task.yield()
        }
        service.start()
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)

        #expect(service.position == realPosition)
    }

    @Test func keepsTheFakePositionForTheNextLaunch() async {
        makeService().use(.fake(chatelet))

        let nextLaunch = makeService()
        nextLaunch.start()
        await waitForPosition(chatelet.coordinate, in: nextLaunch)

        #expect(nextLaunch.source == .fake(chatelet))
        #expect(nextLaunch.position == chatelet.coordinate)
    }

    @Test func ignoresFakePositionsWhenTheyAreNotAllowed() async {
        LocationSourceStore(storage: storage).save(.fake(chatelet))
        let service = makeService(allowsFakePosition: false)
        service.start()
        service.use(.fake(chatelet))
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)

        #expect(service.allowsFakePosition == false)
        #expect(service.source == .realGPS)
        #expect(service.position == realPosition)
    }

    @Test func reportsADeniedPermissionAndDropsThePosition() async {
        let service = makeService()
        service.start()
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)
        gps.report(.permissionDenied)
        await waitForProblem(.permissionDenied, in: service)

        #expect(service.problem == .permissionDenied)
        #expect(service.position == nil)
    }

    @Test func keepsTheLastPositionWhenLocationIsUnavailable() async {
        let service = makeService()
        service.start()
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)
        gps.report(.unavailable)
        await waitForProblem(.unavailable, in: service)

        #expect(service.problem == .unavailable)
        #expect(service.position == realPosition)
    }

    @Test func clearsTheProblemOnTheNextPosition() async {
        let service = makeService()
        service.start()
        gps.report(.unavailable)
        await waitForProblem(.unavailable, in: service)
        gps.report(realPosition)
        await waitForPosition(realPosition, in: service)

        #expect(service.problem == nil)
    }

    @Test func clearsTheProblemWhenTheSourceChanges() async {
        let service = makeService()
        service.start()
        gps.report(.permissionDenied)
        await waitForProblem(.permissionDenied, in: service)
        service.use(.fake(chatelet))

        #expect(service.problem == nil)
    }

    @Test func stopsThePositionUpdatesWhenReleased() async {
        var service: LocationService? = makeService()
        service?.start()
        #expect(gps.isReporting)

        service = nil
        for _ in 0..<1_000 where gps.isReporting {
            await Task.yield()
        }

        #expect(service == nil)
        #expect(!gps.isReporting)
    }
}
