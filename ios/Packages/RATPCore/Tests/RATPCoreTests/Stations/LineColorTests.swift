import Foundation
import Testing
@testable import RATPCore

struct LineColorTests {
    @Test func readsTheRedGreenAndBlueOfAHexColor() {
        let color = LineColor(background: "ffbe00", text: "000000")

        #expect(color.backgroundRGB == LineColor.RGB(red: 1, green: 190.0 / 255, blue: 0))
        #expect(color.textRGB == LineColor.RGB(red: 0, green: 0, blue: 0))
    }

    @Test(arguments: ["", "fff", "ffbe0", "ffbe000", "#ffbe0", "+ffbe0", "zzzzzz"])
    func hasNoRGBForAColorThatIsNotSixHexDigits(hex: String) {
        #expect(LineColor(background: hex, text: hex).backgroundRGB == nil)
    }

    @Test func givesEveryMetroAndRERLineOfTheStationListItsOfficialColor() throws {
        let lines = try StationCatalog.bundled().stations.flatMap(\.lines)
        var colors: [String: LineColor] = [:]
        for line in lines {
            colors[line.displayName] = line.color
        }

        #expect(lines.allSatisfy { $0.color?.backgroundRGB != nil && $0.color?.textRGB != nil })
        #expect(colors["Metro 1"] == LineColor(background: "ffbe00", text: "000000"))
        #expect(colors["Metro 12"] == LineColor(background: "00643c", text: "ffffff"))
        #expect(colors["Metro 3bis"] == LineColor(background: "82c8e6", text: "000000"))
        #expect(colors["RER A"] == LineColor(background: "eb2132", text: "ffffff"))
    }
}
