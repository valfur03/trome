import Foundation
import Testing
@testable import TROMECore

/// The positions of the background keeper reach the features as the stream's do, so a Live Activity still switches
/// and ends once iOS stops the stream; never over a fake position, and never back to an older position.
@MainActor
@Suite(.realTime)
struct LocationServiceBackgroundFixTests {
    private let gps = ControlledLocationProvider()
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let first = Coordinate(48.8584, 2.2945)
    private let second = Coordinate(48.8600, 2.2950)

    private func makeService() -> LocationService {
        LocationService(realProvider: gps, sourceStore: LocationSourceStore(storage: InMemoryKeyValueStore()))
    }

    private func fix(at coordinate: Coordinate, after seconds: TimeInterval) -> PositionFix {
        PositionFix(coordinate: coordinate, accuracyMeters: 10, timestamp: start.addingTimeInterval(seconds))
    }

    @Test func takesANewerPositionWhileItFollowsTheRealGPS() async {
        let service = makeService()
        service.start()
        gps.report(fix(at: first, after: 0))
        await waitUntil { service.position == first }

        service.takeBackgroundFix(fix(at: second, after: 1))

        #expect(service.position == second)
    }

    @Test func ignoresAPositionNoNewerThanTheLastOne() async {
        let service = makeService()
        service.start()
        gps.report(fix(at: first, after: 5))
        await waitUntil { service.position == first }

        service.takeBackgroundFix(fix(at: second, after: 5))
        service.takeBackgroundFix(fix(at: second, after: 4))

        #expect(service.position == first)
    }

    @Test func ignoresAPositionWhenItDoesNotFollowThePosition() {
        let service = makeService()

        service.takeBackgroundFix(fix(at: second, after: 1))

        #expect(service.position == nil)
    }

    @Test func ignoresAPositionOverAFakePosition() async {
        let chatelet = FakePosition(name: "Châtelet", coordinate: Coordinate(48.85855, 2.34743))
        let service = makeService()
        service.start()
        service.use(.fake(chatelet))
        await waitUntil { service.position == chatelet.coordinate }

        let later = Date(timeIntervalSinceNow: 60)
        service.takeBackgroundFix(PositionFix(coordinate: second, accuracyMeters: 10, timestamp: later))

        #expect(service.position == chatelet.coordinate)
    }
}
