import Foundation
import Testing
@testable import RATPCore

struct PlatformStatusTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let line = TransitLine(mode: .metro, name: "12")

    private func departure(
        leavesIn seconds: TimeInterval,
        arrivesIn arrival: TimeInterval?,
        atStop: Bool = false
    ) -> Departure {
        Departure(
            line: line,
            destination: "Mairie d'Issy",
            time: now.addingTimeInterval(seconds),
            arrivalTime: arrival.map { now.addingTimeInterval($0) },
            isAtStop: atStop
        )
    }

    @Test func isNoneForATrainThatArrivesInAMinuteOrMore() {
        #expect(PlatformStatus(of: departure(leavesIn: 80, arrivesIn: 60), at: now) == nil)
    }

    @Test func isApproachingForATrainThatArrivesInLessThanAMinute() {
        #expect(PlatformStatus(of: departure(leavesIn: 79, arrivesIn: 59), at: now) == .approaching)
    }

    @Test func usesTheDepartureTimeWhenPRIMGivesNoArrivalTime() {
        #expect(PlatformStatus(of: departure(leavesIn: 59, arrivesIn: nil), at: now) == .approaching)
        #expect(PlatformStatus(of: departure(leavesIn: 60, arrivesIn: nil), at: now) == nil)
    }

    @Test func isAtThePlatformBetweenTheArrivalAndTheDeparture() {
        #expect(PlatformStatus(of: departure(leavesIn: 15, arrivesIn: -5), at: now) == .atPlatform)
        #expect(PlatformStatus(of: departure(leavesIn: 15, arrivesIn: 0), at: now) == .atPlatform)
    }

    @Test func isAtThePlatformWhenPRIMSaysTheTrainIsAtTheStop() {
        #expect(PlatformStatus(of: departure(leavesIn: 40, arrivesIn: 20, atStop: true), at: now) == .atPlatform)
    }
}
