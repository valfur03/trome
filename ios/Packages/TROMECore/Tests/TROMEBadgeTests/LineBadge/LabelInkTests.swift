import CoreGraphics
import Testing
@testable import TROMEBadge

/// The rule that places a metro number: the weight of the filled drawing across, the middle of the box down.
struct LabelInkTests {
    @Test func theAnchorIsTheWeightAcrossAndTheMiddleOfTheBoxDown() throws {
        // A bar and a foot, like a small L: the weight is at x 2.5, while the box is centred at x 4.
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: 2, height: 10))
        path.addRect(CGRect(x: 2, y: 0, width: 6, height: 2))
        let ink = try #require(LabelInk(of: path))
        #expect(abs(ink.anchor.x - 2.5) < 0.02)
        #expect(abs(ink.anchor.y - 5) < 0.001)
    }

    @Test func outlinesThatOverlapCountOnce() throws {
        // The outlines of a glyph may overlap; the ink of the overlap is drawn once, so it weighs once.
        // A formula on the outlines would count the left part twice and give x 4.14.
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        path.addRect(CGRect(x: 0, y: 0, width: 4, height: 10))
        let ink = try #require(LabelInk(of: path))
        #expect(abs(ink.anchor.x - 5) < 0.02)
    }

    @Test func theReachIsTheFarthestInkFromTheAnchor() throws {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        let ink = try #require(LabelInk(of: path))
        let corner = 50.0.squareRoot()
        #expect(ink.reach >= corner - 0.01 && ink.reach <= corner + 0.05)
    }

    @Test func nothingDrawnHasNoInk() {
        #expect(LabelInk(of: CGMutablePath()) == nil)
    }
}
