import Foundation
import Testing
@testable import TROMECore

private struct ShortTrip {
    let line: TransitLine
    let station: String
    let destination: String
}

extension LineDirectionsTests {
    private var rerAWest: String { "Saint-Germain-en-Laye / Cergy le Haut / Poissy" }
    private var rerAEast: String { "Boissy-Saint-Léger / Marne-la-Vallée - Chessy" }
    private var rerDSouth: String { "Melun / Malesherbes" }
    private var rerESouthEast: String { "Chelles - Gournay / Tournan" }

    @Test func showsTheNextLaDefenseTrainInTheWestDirectionAtVincennesWithNoSharedQuay() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-vincennes-rer-a-0812",
            at: "Vincennes",
            now: Fixture.date("2026-10-02T06:12:00Z")
        )

        #expect(rows == [
            ShownDirection(label: rerAWest, trains: [
                ShownTrain(destination: "La Défense", minutes: 1),
                ShownTrain(destination: "Cergy le Haut", minutes: 2)
            ]),
            ShownDirection(label: rerAEast, trains: [
                ShownTrain(destination: "Boissy-Saint-Léger", minutes: 4),
                ShownTrain(destination: "Marne-la-Vallée - Chessy", minutes: 7)
            ])
        ])
    }

    @Test func showsTheGoussainvilleAndOrryLaVilleTrainsInTheCreilDirectionAtGareDeLyon() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-gare-de-lyon-rer-d-0815",
            at: "Gare de Lyon",
            rer: "D",
            now: Fixture.date("2026-10-02T06:15:00Z")
        )

        #expect(rows == [
            ShownDirection(label: "Creil", trains: [
                ShownTrain(destination: "Goussainville", minutes: 2),
                ShownTrain(destination: "Orry-la-Ville - Coye", minutes: 5)
            ]),
            ShownDirection(label: rerDSouth, trains: [
                ShownTrain(destination: "Corbeil-Essonnes", minutes: 3),
                ShownTrain(destination: "Melun", minutes: 7)
            ])
        ])
    }

    @Test func showsTheStadeDeFranceAndVilliersLeBelTrainsInTheCreilDirectionAtChatelet() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-chatelet-rer-d-0815",
            at: "Châtelet - Les Halles",
            rer: "D",
            now: Fixture.date("2026-10-02T06:15:00Z")
        )

        #expect(rows == [
            ShownDirection(label: "Creil", trains: [
                ShownTrain(destination: "Stade de France Saint-Denis", minutes: 2),
                ShownTrain(destination: "Villiers-le-Bel - Gonesse - Arnouville", minutes: 9)
            ]),
            ShownDirection(label: rerDSouth, trains: [
                ShownTrain(destination: "Melun", minutes: 4),
                ShownTrain(destination: "Malesherbes", minutes: 11)
            ])
        ])
    }

    @Test func showsTheHaussmannSaintLazareTrainInTheNanterreDirectionAtMagenta() throws {
        let rows = try liveActivityRows(
            of: "stop-monitoring-magenta-rer-e-0815",
            at: "Magenta",
            rer: "E",
            now: Fixture.date("2026-10-02T06:15:00Z")
        )

        #expect(rows == [
            ShownDirection(label: "Nanterre-La-Folie", trains: [
                ShownTrain(destination: "Haussmann Saint-Lazare", minutes: 2),
                ShownTrain(destination: "Nanterre-La-Folie", minutes: 6)
            ]),
            ShownDirection(label: rerESouthEast, trains: [
                ShownTrain(destination: "Chelles - Gournay", minutes: 3),
                ShownTrain(destination: "Tournan", minutes: 8)
            ])
        ])
    }

    @Test func placesATrunkShortTripByWhereItEndsFromTheStation() {
        let rerA = TransitLine(mode: .rer, name: "A", stopIds: ["IDFM:monomodalStopPlace:1"])
        let rerD = TransitLine(mode: .rer, name: "D", stopIds: ["IDFM:monomodalStopPlace:2"])
        let rerE = TransitLine(mode: .rer, name: "E", stopIds: ["IDFM:monomodalStopPlace:3"])
        let cases = [
            ShortTrip(line: rerA, station: "Châtelet - Les Halles", destination: "La Défense"),
            ShortTrip(line: rerA, station: "Nanterre - Préfecture", destination: "La Défense"),
            ShortTrip(line: rerD, station: "Garges - Sarcelles", destination: "Goussainville"),
            ShortTrip(line: rerD, station: "Goussainville", destination: "Orry-la-Ville - Coye"),
            ShortTrip(line: rerD, station: "Louvres", destination: "Goussainville"),
            ShortTrip(line: rerD, station: "Goussainville", destination: "Stade de France Saint-Denis"),
            ShortTrip(line: rerE, station: "Pantin", destination: "Haussmann Saint-Lazare"),
            ShortTrip(line: rerE, station: "Neuilly - Porte Maillot", destination: "Haussmann Saint-Lazare")
        ]

        let sides = cases.map { trip in
            let ends = trip.line.ends?.sides.map { $0.joined(separator: " / ") } ?? []
            let result = directions(of: trip.line, at: trip.station, [
                train(trip.line, to: trip.destination, inMinutes: 1, from: rerQuay(9))
            ])
            return result.first { !$0.trains.isEmpty }.flatMap { ends.firstIndex(of: $0.label) }
        }

        #expect(sides == [0, 1, 0, 0, 1, 1, 0, 1])
    }

    @Test func namesOnlyStationsOfTheLineInTheTrunkOfEachRERLine() throws {
        let catalog = try StationCatalog.bundled()
        for name in ["A", "D", "E"] {
            let line = try #require(TransitLine(mode: .rer, name: name, stopIds: []).ends)
            let lineStations = Set(catalog.stations
                .filter { $0.lines.contains { $0.mode == .rer && $0.name == name } }
                .map(\.name))
            #expect(line.trunkStations.allSatisfy(lineStations.contains), "RER \(name)")
            #expect(Set(line.trunkStations).count == line.trunkStations.count, "RER \(name)")
        }
    }
}
