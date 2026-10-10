import Foundation
import Testing
@testable import TROMECore

/// A phone that ran out of battery in Paris and started again: in the 25 seconds after the launch, iOS said that it
/// was inside the areas of 21 stations across the city, with no new position, and the app notified each of them.
/// The first real position then put the phone 378 m from Mairie des Lilas, the nearest station.
/// The stations and their order are the ones of the wake log of that phone.
extension AutoLiveActivityModelTests {
    private static let reportedAfterTheRestart = [
        "Magenta", "Jacques Bonsergent", "Gare du Nord", "Saint-Ambroise", "Château d'Eau", "Chemin Vert",
        "Télégraphe", "Richard-Lenoir", "Gambetta", "Mairie des Lilas", "Voltaire", "Bréguet-Sabin",
        "Arts et Métiers", "Porte de Bagnolet", "Porte de Pantin", "Botzaris", "Saint-Fargeau", "Colonel Fabien",
        "Gare de l'Est", "Louis Blanc", "Jourdain"
    ]
    private static let riderPlace = Coordinate(48.8831, 2.416324)

    private var decisionLinesAfterTheRestart: [String] {
        wakeLog.entries.filter { $0.kind == .decision }.map(\.text).reversed()
    }

    private func entered(_ station: Station) -> RegionEvent {
        .entered(regionId: "arrival:\(station.id)")
    }

    @Test(arguments: [false, true], [false, true])
    func notifiesNoStationThatIOSReportsAfterARestartWithNoPositionThere(
        hasAPositionFromBeforeTheRestart: Bool,
        remembersTheLastArrival: Bool
    ) async throws {
        let paris = try StationCatalog.bundled()
        let stations = try Self.reportedAfterTheRestart.map { name in
            try #require(paris.stations.first { $0.name == name })
        }
        let mairieDesLilas = try #require(stations.first { $0.name == "Mairie des Lilas" })
        if remembersTheLastArrival {
            AutoLiveActivityStore(storage: storage).save(AutoLiveActivityState(arrivalStationId: mairieDesLilas.id))
        }
        let beforeTheRestart = hasAPositionFromBeforeTheRestart
            ? PositionFix(coordinate: Self.riderPlace, accuracyMeters: 10, timestamp: clock.now - 515)
            : nil
        let model = makeModel(catalog: paris)
        gps.givesACurrentFix = false

        for station in stations.prefix(10) {
            await model.handleRegionEvent(entered(station), lastKnownFix: beforeTheRestart)
        }
        gps.currentFixCoordinate = Self.riderPlace
        gps.givesACurrentFix = true
        for station in stations.dropFirst(10) {
            await model.handleRegionEvent(entered(station), lastKnownFix: beforeTheRestart)
        }

        #expect(notifier.notified.isEmpty)
        #expect(client.started.isEmpty)
        let firstReason = hasAPositionFromBeforeTheRestart
            ? "the position is ±10 m and 515 s old"
            : "iOS gave no position"
        #expect(decisionLinesAfterTheRestart.first == "No arrival at Magenta: \(firstReason)")
        #expect(decisionLinesAfterTheRestart.contains("No arrival at Voltaire: the position is 3861 m away"))
        let plannedCenters = watcher.watched.compactMap { $0.first { $0.id == "refresh" }?.center }
        #expect(!plannedCenters.isEmpty)
        #expect(plannedCenters.allSatisfy { $0 == Self.riderPlace })
    }

    @Test func notifiesOnceWhenIOSReportsAnArrivalAndThenGivesAPositionAtTheStation() async {
        let model = makeModel()
        gps.currentFixCoordinate = Places.fiftyMetersFromA

        await model.handleRegionEvent(entered(Places.stationA), lastKnownFix: nil)
        await model.handleRegionEvent(entered(Places.stationA), lastKnownFix: nil)

        #expect(notifier.notified == [Places.stationA])
        #expect(gps.currentFixRequestCount == 2)
    }

    @Test func refusesAReportedArrivalWithNoNewRequestWhenARecentTrustedPositionIsFar() async {
        let model = makeModel()
        gps.currentFixCoordinate = Places.fiftyMetersFromA
        let far = PositionFix(coordinate: Places.fourHundredMetersFromA, accuracyMeters: 10, timestamp: clock.now - 5)

        await model.handleRegionEvent(entered(Places.stationA), lastKnownFix: far)

        #expect(notifier.notified.isEmpty)
        #expect(gps.currentFixRequestCount == 0)
        #expect(decisionLinesAfterTheRestart.first == "No arrival at Station A: the position is 400 m away")
    }

    @Test func refusesAReportedArrivalWhenIOSGivesOnlyARoughPosition() async {
        let model = makeModel()
        gps.givesACurrentFix = false
        let rough = PositionFix(coordinate: Places.fiftyMetersFromA, accuracyMeters: 1_000, timestamp: clock.now)

        await model.handleRegionEvent(entered(Places.stationA), lastKnownFix: rough)

        #expect(notifier.notified.isEmpty)
        #expect(decisionLinesAfterTheRestart.first == "No arrival at Station A: the position is ±1000 m and 0 s old")
    }
}
