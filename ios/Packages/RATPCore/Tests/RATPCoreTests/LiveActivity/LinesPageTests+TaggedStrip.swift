import Foundation
import Testing
@testable import RATPCore

extension LinesPageTests {
    static let taggedStations = [
        "Aubervilliers - Pantin - Quatre Chemins", "Cadet", "Censier - Daubenton", "Châtillon - Montrouge",
        "Corentin Cariou", "Crimée", "Fort d'Aubervilliers", "Gaîté", "La Courneuve - 8 Mai 1945", "La Fourche",
        "Le Peletier", "Les Gobelins", "Liège", "Malakoff - Plateau de Vanves", "Malakoff - Rue Étienne Dolet",
        "Pernety", "Place Monge", "Plaisance", "Poissonnière", "Pont Marie (Cité des Arts)", "Pont Neuf",
        "Porte de Vanves", "Porte de la Villette", "Riquet", "Saint-François-Xavier", "Sully - Morland", "Tolbiac",
        "Varenne"
    ]
    static let taggedStationsWithOtherLines = [
        "Champs-Élysées - Clemenceau", "Chaussée d'Antin - La Fayette", "Château Landon", "Châtelet", "Duroc",
        "Gare de l'Est", "Havre-Caumartin", "Invalides", "Jussieu", "Les Halles", "Louis Blanc", "Maison Blanche",
        "Miromesnil", "Montparnasse Bienvenue", "Opéra", "Palais Royal - Musée du Louvre", "Place d'Italie",
        "Place de Clichy", "Pyramides", "Saint-Augustin", "Saint-Lazare", "Stalingrad"
    ]

    @Test func drawsTheTaggedStripAtTheTrunkAndForkStationsOfLines7And13() throws {
        let catalog = try StationCatalog.bundled()
        let tagged = try catalog.stations.filter { $0.lines.contains { $0.mode == .metro } }.filter { station in
            try pagesWithFakeTrains(at: station.name).contains { page in
                page.panamStripsLine?.directions.contains { $0.branchEnds != nil } == true
            }
        }
        let withOneLine = tagged.filter { $0.lines.count == 1 && catalog.hubStations(of: $0).count == 1 }

        #expect(withOneLine.map(\.name) == Self.taggedStations)
        #expect(Set(tagged.map(\.name)) == Set(Self.taggedStations + Self.taggedStationsWithOtherLines))
    }

    @Test(arguments: ["Liège", "Tolbiac", "La Fourche", "Châtillon - Montrouge", "La Courneuve - 8 Mai 1945"])
    func drawsOneTaggedStripAndOnePlainStrip(station: String) throws {
        let line = try #require(try pageWithFakeTrains(at: station).panamStripsLine)

        #expect(line.directions.filter { $0.branchEnds != nil }.count == 1)
        #expect(line.directions.count <= 2)
    }

    @Test(arguments: ["Porte d'Italie", "Villejuif - Louis Aragon", "Brochant", "Basilique de Saint-Denis"])
    func drawsPlainStripsOnABranch(station: String) throws {
        let line = try #require(try pageWithFakeTrains(at: station).panamStripsLine)

        #expect(line.directions.allSatisfy { $0.branchEnds == nil })
    }

    @Test(arguments: ["Maison Blanche", "Gare de l'Est", "Place de Clichy", "Château Landon"])
    func drawsTheTaggedStripOnThePageOfTheForkLineAtAStationWithAnotherLineOrAHub(station: String) throws {
        let pages = try pagesWithFakeTrains(at: station)
        let forkLine = try #require(pages.compactMap(\.panamStripsLine).first { ["7", "13"].contains($0.line.name) })

        #expect(forkLine.directions.filter { $0.branchEnds != nil }.count == 1)
    }

    @Test func marksEachTrainWithTheEndOfItsBranchInTheOrderOfTheLine() throws {
        let line = try #require(try pageWithFakeTrains(at: "Liège").panamStripsLine)
        let north = try #require(line.directions.first { $0.branchEnds != nil })

        #expect(north.branchEnds == Self.line13NorthEnds)
        #expect(north.trains.map(north.branchEndIndex(of:)) == [0, 1])
    }

    @Test(arguments: [
        ([1, 0], [1, 0]),
        ([0, 0], [0, 0]),
        ([1, 1], [1, 1]),
        ([1], [1])
    ])
    func marksEachTrainWithItsEndWhateverTheOrderOfTheTrains(ends: [Int], marks: [Int]) {
        let direction = Self.line13North(trainsTo: ends.map { Self.line13NorthEnds[$0] })

        #expect(direction.branchEnds == Self.line13NorthEnds)
        #expect(direction.trains.map(direction.branchEndIndex(of:)) == marks)
        #expect(page(with: direction).panamStripsLine != nil)
    }

    @Test func keepsTheRowsWhileATrainOfTheTaggedDirectionEndsAtAThirdPlace() {
        let direction = Self.line13North(trainsTo: ["Porte de Saint-Ouen", Self.line13NorthEnds[1]])

        #expect(direction.branchEndIndex(of: direction.trains[0]) == nil)
        #expect(page(with: direction).panamStripsLine == nil)
    }

    @Test func drawsTheTaggedStripWithNoTrain() {
        let direction = Self.line13North(trainsTo: [])

        #expect(page(with: direction).panamStripsLine?.directions == [direction])
    }

    @Test func leavesRoomForATwoLineStationNameOnlyWithOneStripOrNone() throws {
        let line = try #require(try pageWithFakeTrains(at: "Liège").panamStripsLine)
        var oneStrip = line
        oneStrip.directions.removeLast()
        var noStrip = line
        noStrip.directions = []

        #expect(!line.hasRoomForATwoLineStationName)
        #expect(oneStrip.hasRoomForATwoLineStationName)
        #expect(noStrip.hasRoomForATwoLineStationName)
    }

    private static let line13NorthEnds = ["Saint-Denis - Université", "Asnières - Gennevilliers - Les Courtilles"]

    private static func line13North(trainsTo ends: [String]) -> LineDirection {
        LineDirection(
            label: line13NorthEnds.joined(separator: " / "),
            trains: ends.enumerated().map { index, end in
                .init(time: Date(timeIntervalSince1970: 1_800_000_000 + Double(index + 1) * 120), destination: end)
            },
            branchEnds: line13NorthEnds
        )
    }

    private func page(with direction: LineDirection) -> LinesPage {
        let line13 = TransitLine(mode: .metro, name: "13")
        return LinesPage(
            lines: [LineTrains(line: line13, directions: [direction], hasADirectionWithTwoEnds: true)],
            allLines: [line13],
            firstIndex: 0,
            soonestTrain: nil
        )
    }
}
