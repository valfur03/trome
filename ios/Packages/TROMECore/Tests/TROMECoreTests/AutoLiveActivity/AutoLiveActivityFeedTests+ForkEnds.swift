import Foundation
import Testing
@testable import TROMECore

extension AutoLiveActivityModelTests {
    private static let saintDenis = "Saint-Denis-Université"
    private static let asnieres = "Asnières-Gennevilliers Les Courtilles"
    private static let northQuay = "STIF:StopPoint:Q:22225:"

    private func liege() throws -> Station {
        try #require(try StationCatalog.bundled().stations.first { $0.name == "Liège" })
    }

    private func north(_ destination: String, leavesAfter seconds: TimeInterval, of line: TransitLine) -> Departure {
        let time = clock.now.addingTimeInterval(seconds)
        return Departure(
            line: line,
            destination: destination,
            time: time,
            quayRef: Self.northQuay,
            arrivalTime: time.addingTimeInterval(-20)
        )
    }

    @Test func showsTheNextTwoTrainsOfAForkEndWithTheSameUpdateThatRemovesItsTrainThatLeft() async throws {
        let station = try liege()
        let line13 = try #require(station.lines.first)
        let start = clock.now
        provider.answer(.success([
            north(Self.saintDenis, leavesAfter: 100, of: line13),
            north(Self.asnieres, leavesAfter: 220, of: line13),
            north(Self.saintDenis, leavesAfter: 460, of: line13),
            north(Self.asnieres, leavesAfter: 700, of: line13)
        ]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { !$0.saintDenisTimes.isEmpty } }
        model.setAppPhase(.background)
        provider.answer(.success([
            north(Self.asnieres, leavesAfter: 220, of: line13),
            north(Self.saintDenis, leavesAfter: 460, of: line13),
            north(Self.asnieres, leavesAfter: 700, of: line13),
            north(Self.saintDenis, leavesAfter: 940, of: line13)
        ]), for: station)
        // The answer comes at once: the wait for a slow answer must not end first, however busy the machine.
        clock.holdTimers(of: BackgroundTrainsRefresh.answerWaitInPlaceOfARedraw)

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        await waitUntil { client.updates.contains { $0.updatedAt >= start.addingTimeInterval(110) } }

        let afterTheDeparture = client.updates.filter {
            $0.updatedAt >= start.addingTimeInterval(100) && $0.updatedAt < start.addingTimeInterval(400)
        }
        let next = [460, 940].map { start.addingTimeInterval($0) }
        #expect(!afterTheDeparture.isEmpty)
        #expect(afterTheDeparture.allSatisfy { $0.saintDenisTimes == next })
    }

    @Test func dropsTheTrainThatLeftAfterAShortWaitWhenTheAnswerOfTheCallAtItsDepartureIsSlow() async throws {
        let station = try liege()
        let line13 = try #require(station.lines.first)
        let start = clock.now
        provider.answer(.success([
            north(Self.saintDenis, leavesAfter: 100, of: line13),
            north(Self.asnieres, leavesAfter: 220, of: line13),
            north(Self.saintDenis, leavesAfter: 460, of: line13)
        ]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { !$0.saintDenisTimes.isEmpty } }
        model.setAppPhase(.background)
        provider.answer(.success([
            north(Self.asnieres, leavesAfter: 220, of: line13),
            north(Self.saintDenis, leavesAfter: 460, of: line13),
            north(Self.saintDenis, leavesAfter: 940, of: line13)
        ]), for: station)
        provider.holdAnswers()

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        let redrawn = start.addingTimeInterval(100 + BackgroundTrainsRefresh.answerWaitInPlaceOfARedraw)
        await waitUntil { client.updates.contains { $0.updatedAt >= redrawn } }
        let whileTheAnswerIsLate = client.updates.last
        provider.releaseAnswers()
        await waitUntil {
            client.updates.last?.saintDenisTimes.count == 2 && client.updates.last != whileTheAnswerIsLate
        }

        #expect(whileTheAnswerIsLate?.updatedAt == redrawn)
        #expect(whileTheAnswerIsLate?.saintDenisTimes == [start.addingTimeInterval(460)])
        #expect(client.updates.last?.saintDenisTimes == [460, 940].map { start.addingTimeInterval($0) })
    }

    @Test func dropsTheTrainThatLeftAndKeepsTheOthersWhenTheCallAtItsDepartureFails() async throws {
        let station = try liege()
        let line13 = try #require(station.lines.first)
        let start = clock.now
        provider.answer(.success([
            north(Self.saintDenis, leavesAfter: 100, of: line13),
            north(Self.asnieres, leavesAfter: 220, of: line13),
            north(Self.saintDenis, leavesAfter: 460, of: line13)
        ]), for: station)
        let model = makeModel(catalog: StationCatalog(stations: [station]))
        await arrive(at: station.coordinate, in: model)
        await waitUntil { client.updates.contains { !$0.saintDenisTimes.isEmpty } }
        model.setAppPhase(.background)
        provider.answer(.failure(.unreachable), for: station)
        // The failure comes at once: the wait for a slow answer must not end first, however busy the machine.
        clock.holdTimers(of: BackgroundTrainsRefresh.answerWaitInPlaceOfARedraw)

        clock.letTimersFire(upTo: BackgroundTrainsRefresh.maximumDelay)
        // An update after the departure comes only once the work at the departure is done.
        await waitUntil { client.updates.contains { $0.updatedAt > start.addingTimeInterval(100) } }

        let atTheDeparture = client.updates.last { $0.updatedAt == start.addingTimeInterval(100) }
        #expect(atTheDeparture?.saintDenisTimes == [start.addingTimeInterval(460)])
        #expect(atTheDeparture?.isMarkedStale == false)
        #expect(atTheDeparture?.staleDate == start.addingTimeInterval(220))
    }
}

private extension StationActivityAttributes.ContentState {
    var saintDenisTimes: [Date] {
        let ends = trains.linesPage?.lines.flatMap(\.directions).compactMap(\.trainsOfEachEnd).flatMap(\.self) ?? []
        return ends.first { $0.end.hasPrefix("Saint-Denis") }?.trains.map(\.time) ?? []
    }
}
