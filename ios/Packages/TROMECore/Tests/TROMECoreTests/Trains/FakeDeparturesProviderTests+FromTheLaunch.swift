import Foundation
import Testing
@testable import TROMECore

/// The default fake trains count from the launch, not from each fetch: with the app running, a tester who watches a
/// train sees it leave at its time, and never sees its wait rise again at the next fetch.
struct FakeDeparturesProviderFromTheLaunchTests {
    let launch = Date(timeIntervalSince1970: 1_000_000)
    let line7 = TransitLine(mode: .metro, name: "7")
    let line12 = TransitLine(mode: .metro, name: "12")

    func station(_ name: String, _ lines: [TransitLine]) -> Station {
        Station(id: name, name: name, coordinate: Coordinate(48.85, 2.35), lines: lines)
    }

    func time(inMinutes minutes: Double) -> Date {
        launch.addingTimeInterval(minutes * 60)
    }

    func departures(at stations: [Station], minutesAfterTheLaunch minutes: Double) async throws -> [Departure] {
        let now = time(inMinutes: minutes)
        return try await FakeDeparturesProvider(start: launch, now: { now }).departures(at: stations)
    }

    func firstTime(toward end: String, in departures: [Departure]) -> Date? {
        departures.filter { $0.destination == end }.map(\.time).min()
    }

    @Test func aFetchAfterTwoMinutesKeepsTheFirstTrainThreeMinutesAfterTheLaunch() async throws {
        let result = try await departures(at: [station("Abbesses", [line12])], minutesAfterTheLaunch: 2 + 10.0 / 60)

        #expect(firstTime(toward: "Mairie d'Aubervilliers", in: result) == time(inMinutes: 3))
        #expect(firstTime(toward: "Mairie d'Issy", in: result) == time(inMinutes: 4))
    }

    @Test func aFetchOnceTheFirstTrainLeftGivesTheNextTrains() async throws {
        let result = try await departures(at: [station("Abbesses", [line12])], minutesAfterTheLaunch: 3)

        #expect(result.filter { $0.destination == "Mairie d'Aubervilliers" }.map(\.time) == [
            time(inMinutes: 7), time(inMinutes: 11), time(inMinutes: 15), time(inMinutes: 19)
        ])
        #expect(firstTime(toward: "Mairie d'Issy", in: result) == time(inMinutes: 4))
    }

    @Test func aFetchAfterAnHourInTheBackgroundStillGivesTrains() async throws {
        let result = try await departures(at: [station("Abbesses", [line12])], minutesAfterTheLaunch: 61)

        #expect(result.filter { $0.destination == "Mairie d'Issy" }.map(\.time) == [
            time(inMinutes: 64), time(inMinutes: 68), time(inMinutes: 72), time(inMinutes: 76)
        ])
    }

    @Test func eachTrainOfABranchedSideKeepsItsEndFromOneFetchToTheNext() async throws {
        let poissonniere = [station("Poissonnière", [line7])]
        let atTheLaunch = try await departures(at: poissonniere, minutesAfterTheLaunch: 0)
        let afterTheFirstTrain = try await departures(at: poissonniere, minutesAfterTheLaunch: 5)

        let laterTrains = Set(afterTheFirstTrain)
        #expect(atTheLaunch.filter { $0.time > time(inMinutes: 5) }.allSatisfy(laterTrains.contains))
    }

    @Test func aWaitRisesOnlyWhenItsTrainLeft() async throws {
        let abbesses = [station("Abbesses", [line12])]
        var shown: [String: Date] = [:]
        for step in 0...180 {
            let minutes = Double(step) / 6
            let result = try await departures(at: abbesses, minutesAfterTheLaunch: minutes)
            for end in ["Mairie d'Aubervilliers", "Mairie d'Issy"] {
                let first = try #require(firstTime(toward: end, in: result))
                if let before = shown[end], first != before {
                    #expect(before <= time(inMinutes: minutes), "\(end) at \(minutes) min: \(before) left too early")
                    #expect(first > before, "\(end) at \(minutes) min: the next train comes before the last one")
                }
                shown[end] = first
            }
        }
    }
}
