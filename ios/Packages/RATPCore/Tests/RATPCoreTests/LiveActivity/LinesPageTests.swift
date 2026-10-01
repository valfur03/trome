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
        mode: TransitMode = .metro,
        directions: Int,
        firstTrainInMinutes minutes: Double = 5,
        stationName: String? = nil
    ) -> LineTrains {
        LineTrains(
            line: TransitLine(mode: mode, name: name),
            directions: (0..<directions).map { index in
                LineDirection(
                    label: "\(name) end \(index)",
                    times: [time(inMinutes: minutes + Double(index)), time(inMinutes: minutes + Double(index) + 6)]
                )
            },
            stationName: stationName
        )
    }

    @Test func showsOneRERLinePerPageWithTheTrainsOfBothDirections() {
        let lines = [
            line("A", mode: .rer, directions: 2),
            line("B", mode: .rer, directions: 2),
            line("D", mode: .rer, directions: 2)
        ]

        let pages = [0, 1, 2].map { LinesPage(showing: lines, from: $0) }

        #expect(pages.map { $0.lines.map(\.line.name) } == [["A"], ["B"], ["D"]])
        #expect(pages.allSatisfy { $0.lines.flatMap(\.directions).allSatisfy { $0.trains.count == 2 } })
        #expect(pages.map(\.nextFirstIndex) == [1, 2, 0])
        #expect(pages.map(\.otherLineCount) == [2, 2, 2])
        #expect(pages[0].allLines.map(\.name) == ["A", "B", "D"])
    }

    @Test func showsOneMetroLinePerPageWithTheTrainsOfBothDirections() {
        let lines = [line("1", directions: 2), line("4", directions: 1), line("7", directions: 2)]

        let pages = [0, 1, 2].map { LinesPage(showing: lines, from: $0) }

        #expect(pages.map { $0.lines.map(\.line.name) } == [["1"], ["4"], ["7"]])
        #expect(pages[0].lines.flatMap(\.directions).allSatisfy { $0.trains.count == 2 })
        #expect(pages.map(\.nextFirstIndex) == [1, 2, 0])
        #expect(pages.map(\.otherLineCount) == [2, 2, 2])
    }

    @Test func goesThroughTheMetroAndRERLinesOneLinePerPageInTheirOrder() {
        let lines = [
            line("4", directions: 1),
            line("A", mode: .rer, directions: 1),
            line("B", mode: .rer, directions: 1),
            line("14", directions: 1)
        ]

        var pages = [LinesPage(showing: lines, from: 0)]
        while let last = pages.last, last.nextFirstIndex != 0 {
            pages.append(LinesPage(showing: lines, from: last.nextFirstIndex))
        }

        #expect(pages.map { $0.lines.map(\.line.name) } == [["4"], ["A"], ["B"], ["14"]])
        #expect(pages.map(\.otherLineCount) == [3, 3, 3, 3])
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

    @Test func showsAnRERLineWithNoDirectionOnAPageOfItsOwn() {
        let lines = [line("A", mode: .rer, directions: 2), line("B", mode: .rer, directions: 0)]

        let page = LinesPage(showing: lines, from: 1)

        #expect(page.lines.map(\.line.name) == ["B"])
        #expect(page.lines[0].hasNoTrain)
    }

    @Test func keepsTheNameOfTheStationThatServesALineWhenItKeepsOneTrainPerDirection() {
        let lines = [line("E", mode: .rer, directions: 3, stationName: "Haussmann Saint-Lazare")]

        let page = LinesPage(showing: lines, from: 0)

        #expect(page.lines.map(\.stationName) == ["Haussmann Saint-Lazare"])
        #expect(page.lines.flatMap(\.directions).map(\.trains.count) == [1, 1, 1])
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
        let lines = [
            line("A", mode: .rer, directions: 2),
            line("B", mode: .rer, directions: 2),
            line("7", directions: 2)
        ]

        let first = LinesPage(showing: lines, from: 0)
        let second = LinesPage(showing: lines, from: first.nextFirstIndex)

        let third = LinesPage(showing: lines, from: second.nextFirstIndex)

        #expect(second.lines.map(\.line.name) == ["B"])
        #expect(third.firstIndex == 2)
        #expect(third.lines.map(\.line.name) == ["7"])
        #expect(third.nextFirstIndex == 0)
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
        var lineD = line("D", mode: .rer, directions: 2)
        let later = LineDirection(label: "Malesherbes", times: [], nextTrainIsOverAnHourAway: true)
        lineD.directions.append(later)

        let page = LinesPage(showing: [lineD], from: 0)

        #expect(page.lines[0].directions.map(\.trains.count) == [1, 1, 0])
        #expect(page.lines[0].directions.last == later)
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
