import Foundation
import Testing
@testable import RATPCore

extension LinesPageTests {
    @Test(arguments: [
        "Châtelet - Les Halles", "Gare du Nord", "Auber", "Invalides", "Haussmann Saint-Lazare", "Boigneville"
    ])
    func drawsEveryRERPageInSielRowsAndNoMetroPage(station: String) throws {
        let pages = try pagesWithFakeTrains(at: station)

        for page in pages {
            let line = try #require(page.lines.first)
            #expect(page.sielRowsLine == (line.line.mode == .rer ? line : nil))
        }
        #expect(pages.contains { $0.sielRowsLine != nil })
    }

    @Test func drawsTheSielRowsOfAnRERLineWithNoTrain() {
        let line = LineTrains(line: TransitLine(mode: .rer, name: "C"), directions: [])

        #expect(LinesPage(showing: [line], from: 0).sielRowsLine == line)
    }
}
