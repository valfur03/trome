import Foundation
import Testing
@testable import RATPCore

struct LinesPageTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    private func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    private func line(
        _ name: String,
        directions: Int,
        firstTrainInMinutes minutes: Double = 5,
        stationName: String? = nil
    ) -> LineTrains {
        LineTrains(
            line: TransitLine(mode: .metro, name: name),
            directions: (0..<directions).map { index in
                LineDirection(
                    label: "\(name) end \(index)",
                    times: [time(inMinutes: minutes + Double(index)), time(inMinutes: minutes + Double(index) + 6)]
                )
            },
            stationName: stationName
        )
    }

    @Test func showsAsManyLinesAsFitInFourRowsWithOneTrainEach() {
        let lines = [line("1", directions: 2), line("4", directions: 2), line("7", directions: 2)]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.lines.map(\.line.name) == ["1", "4"])
        #expect(page.lines.flatMap(\.directions).allSatisfy { $0.trains.count == 1 })
        #expect(page.allLines.map(\.name) == ["1", "4", "7"])
        #expect(page.hasOtherLines)
        #expect(page.otherLineCount == 1)
    }

    @Test func keepsTwoTrainsInEachDirectionWhenThePageShowsTwoDirections() {
        let page = LinesPage(showing: [line("12", directions: 2)], from: 0)

        #expect(page.lines == [line("12", directions: 2)])
        #expect(!page.hasOtherLines)
        #expect(page.otherLineCount == 0)
    }

    @Test func showsOnlyTheNextTrainOfEachDirectionWhenALineHasThreeDirections() {
        let page = LinesPage(showing: [line("B", directions: 3)], from: 0)

        #expect(page.lines.flatMap(\.directions).map(\.trains.count) == [1, 1, 1])
    }

    @Test func showsAtLeastOneLineEvenWhenItNeedsMoreThanFourRows() {
        let page = LinesPage(showing: [line("1", directions: 2), line("B", directions: 5)], from: 1)

        #expect(page.lines.map(\.line.name) == ["B"])
    }

    @Test func countsARowForALineWithoutDirection() {
        let lines = [
            line("1", directions: 2),
            line("4", directions: 0),
            line("7", directions: 1),
            line("11", directions: 1)
        ]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.lines.map(\.line.name) == ["1", "4", "7"])
    }

    @Test func countsARowForTheNameOfTheStationThatServesALine() {
        let lines = [line("3", directions: 2), line("13", directions: 2, stationName: "Saint-Lazare")]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.lines.map(\.line.name) == ["3"])
    }

    @Test func keepsTheNameOfTheStationThatServesALineWhenItKeepsOneTrainPerDirection() {
        let lines = [line("12", directions: 2, stationName: "Saint-Lazare"), line("13", directions: 1)]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.lines.map(\.stationName) == ["Saint-Lazare", nil])
        #expect(page.lines.flatMap(\.directions).allSatisfy { $0.trains.count == 1 })
    }

    @Test func keepsOnlyTheNextTrainOfEachDirectionAndTheRestOfThePage() {
        let branches = LineTrains(line: TransitLine(mode: .rer, name: "A"), directions: [
            LineDirection(label: "Poissy / Cergy le Haut", trains: [
                LineDirection.Train(time: time(inMinutes: 2), destination: "Poissy"),
                LineDirection.Train(time: time(inMinutes: 13), destination: "Cergy le Haut")
            ]),
            LineDirection(label: "Marne-la-Vallée Chessy", times: [time(inMinutes: 1), time(inMinutes: 11)])
        ], stationName: "Auber")
        let page = LinesPage(showing: [branches, line("3", directions: 2)], from: 0)

        let island = page.keepingOnlyTheNextTrains

        #expect(island.lines.map(\.directions) == [[
            LineDirection(label: "Poissy / Cergy le Haut", trains: [
                LineDirection.Train(time: time(inMinutes: 2), destination: "Poissy")
            ]),
            LineDirection(label: "Marne-la-Vallée Chessy", times: [time(inMinutes: 1)])
        ]])
        #expect(island.lines[0].directions.map(\.name) == ["Poissy", "Marne-la-Vallée Chessy"])
        #expect(island.lines.map(\.stationName) == ["Auber"])
        #expect(island.allLines == page.allLines)
        #expect(island.firstIndex == page.firstIndex)
        #expect(island.soonestTrain == page.soonestTrain)
        #expect(island.nextFirstIndex == page.nextFirstIndex)
    }

    @Test func goesToTheLineAfterThePageThenBackToTheFirstLine() {
        let lines = [line("1", directions: 2), line("4", directions: 2), line("7", directions: 2)]

        let first = LinesPage(showing: lines, from: 0)
        let second = LinesPage(showing: lines, from: first.nextFirstIndex)

        #expect(second.firstIndex == 2)
        #expect(second.lines.map(\.line.name) == ["7"])
        #expect(second.nextFirstIndex == 0)
    }

    @Test func startsAtTheFirstLineWhenTheAskedLineDoesNotExist() {
        let page = LinesPage(showing: [line("1", directions: 2)], from: 3)

        #expect(page.firstIndex == 0)
        #expect(page.lines.map(\.line.name) == ["1"])
    }

    @Test func knowsTheSoonestTrainOfEveryLineAlsoOffThePage() {
        let lines = [
            line("1", directions: 2, firstTrainInMinutes: 4),
            line("4", directions: 2, firstTrainInMinutes: 6),
            line("7", directions: 2, firstTrainInMinutes: 1)
        ]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.soonestTrain == SoonestTrain(line: TransitLine(mode: .metro, name: "7"), time: time(inMinutes: 1)))
    }

    @Test func hasNoSoonestTrainWhenNoLineHasATrain() {
        let empty = LineTrains(line: TransitLine(mode: .metro, name: "1"), directions: [
            LineDirection(label: "La Défense", times: [])
        ])

        #expect(LinesPage(showing: [empty], from: 0).soonestTrain == nil)
    }

    @Test func keepsSayingTheNextTrainIsOverAnHourAwayWhenItShowsOnlyOneTrainPerDirection() {
        let later = LineTrains(line: TransitLine(mode: .rer, name: "D"), directions: [
            LineDirection(label: "Malesherbes", times: [], nextTrainIsOverAnHourAway: true)
        ])

        let page = LinesPage(showing: [line("1", directions: 2), later], from: 0)

        #expect(page.lines[1].directions == later.directions)
    }

    @Test func saysTheNextTrainIsOverAnHourAwayOnlyWhenNoLineHasATrainWithinTheHour() {
        let later = LineTrains(line: TransitLine(mode: .rer, name: "D"), directions: [
            LineDirection(label: "Malesherbes", times: [], nextTrainIsOverAnHourAway: true)
        ])
        let noTrains = LineTrains(line: TransitLine(mode: .rer, name: "C"), directions: [
            LineDirection(label: "Versailles Château Rive Gauche", times: [])
        ])

        #expect(LinesPage(showing: [noTrains, later], from: 0).nextTrainIsOverAnHourAway)
        #expect(!LinesPage(showing: [line("1", directions: 1), later], from: 0).nextTrainIsOverAnHourAway)
        #expect(!LinesPage(showing: [noTrains], from: 0).nextTrainIsOverAnHourAway)
    }

    @Test func showsSeveralLinesOnlyWhenTheStationHasMoreThanOneLine() {
        let oneLine = LinesPage(showing: [line("12", directions: 2)], from: 0)
        let severalLines = LinesPage(showing: [line("1", directions: 2), line("4", directions: 2)], from: 0)

        #expect(!oneLine.showsSeveralLines)
        #expect(severalLines.showsSeveralLines)
    }

    @Test func tellsWhichLinesThePageShows() {
        let lines = [line("1", directions: 2), line("4", directions: 2), line("7", directions: 2)]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.isShown(TransitLine(mode: .metro, name: "4")))
        #expect(!page.isShown(TransitLine(mode: .metro, name: "7")))
    }

    @Test func hasNoTrainWhenNoDirectionOfTheLineHasATrain() {
        let line = TransitLine(mode: .metro, name: "4")
        let empty = LineDirection(label: "Porte de Clignancourt", trains: [])
        let withTrain = LineDirection(label: "Bagneux - Lucie Aubrac", times: [Date(timeIntervalSince1970: 1_000)])

        #expect(LineTrains(line: line, directions: []).hasNoTrain)
        #expect(LineTrains(line: line, directions: [empty, empty]).hasNoTrain)
        #expect(!LineTrains(line: line, directions: [empty, withTrain]).hasNoTrain)
    }

    @Test func hasATrainWhenADirectionHasItsNextTrainInOverAnHour() {
        let line = TransitLine(mode: .metro, name: "6")
        let empty = LineDirection(label: "Nation", trains: [])
        let later = LineDirection(label: "Charles de Gaulle-Etoile", trains: [], nextTrainIsOverAnHourAway: true)

        #expect(!LineTrains(line: line, directions: [empty, later]).hasNoTrain)
    }
}
