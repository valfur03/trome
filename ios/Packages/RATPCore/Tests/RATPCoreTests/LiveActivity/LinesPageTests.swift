import Foundation
import Testing
@testable import RATPCore

struct LinesPageTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func time(inMinutes minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    private func line(_ name: String, directions: Int, firstTrainInMinutes minutes: Double = 5) -> LineTrains {
        LineTrains(
            line: TransitLine(mode: .metro, name: name),
            directions: (0..<directions).map { index in
                LineDirection(
                    label: "\(name) end \(index)",
                    times: [time(inMinutes: minutes + Double(index)), time(inMinutes: minutes + Double(index) + 6)]
                )
            }
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
}
