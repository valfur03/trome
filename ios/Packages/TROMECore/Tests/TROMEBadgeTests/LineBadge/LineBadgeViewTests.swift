import Foundation
import SwiftUI
import Testing
import TROMECore
@testable import TROMEBadge

/// Draws the badge of every metro and RER line, at the size of each surface, and measures what is drawn: the ink of
/// the number or letter must be at the centre of the badge, a metro badge must be a circle, the ink must keep off the
/// edge, and it must have the text colour of the line.
@MainActor
struct LineBadgeViewTests {
    static let largestGap: CGFloat = 0.5

    /// The scale of a drawing: one pixel is a sixth of a point, or a third for the biggest badges, so that the test
    /// stays fast; the centre of a box is then within half a pixel, a twelfth or a sixth of a point.
    static func scale(of diameter: CGFloat) -> CGFloat {
        diameter > 40 ? 3 : 6
    }

    /// The badge sizes of each surface: at the default text size, and at the largest text size that it shows
    /// (Apple's sizes: subheadline 15 pt at Large and 49 pt at AX5 on the app screen; footnote 13 pt at Large and
    /// 19 pt at XXXL, the largest of a Live Activity).
    static func diameters(of surface: LineBadgeSurface) -> [CGFloat] {
        switch surface {
        case .header: [surface.diameter, surface.diameter * 21 / 15, surface.diameter * 49 / 15]
        case .lineRow: [surface.diameter, surface.diameter * 19 / 13]
        case .compactIsland: [surface.diameter]
        }
    }

    @Test func everyBadgeIsCentredRoundAndInTheColoursOfItsLine() throws {
        let lines = try Self.everyLine()
        #expect(lines.filter { $0.mode == .metro }.count == 16, "The 16 metro lines, 3bis and 7bis included")
        #expect(lines.filter { $0.mode == .rer }.map(\.name) == ["A", "B", "C", "D", "E"])
        for surface in LineBadgeSurface.allCases {
            for diameter in Self.diameters(of: surface) {
                for line in lines {
                    try check(line, on: surface, diameter: diameter)
                }
            }
        }
    }

    @Test func theBadgeOfTheCompactIslandIsNotSmallerThanBefore() {
        #expect(LineBadgeSurface.compactIsland.diameter >= 21.7)
    }

    private func check(_ line: TransitLine, on surface: LineBadgeSurface, diameter: CGFloat) throws {
        let name = "\(line.displayName) on the \(surface.rawValue) at \(String(format: "%.1f", diameter)) pt"
        let renderer = ImageRenderer(content: LineBadgeView(line: line, diameter: diameter))
        let scale = Self.scale(of: diameter)
        renderer.scale = scale
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage, "\(name): nothing drawn")
        let fill = try #require(line.color?.backgroundRGB, "\(line.displayName) has no colour")
        let text = try #require(line.color?.textRGB, "\(line.displayName) has no text colour")
        let ink = try #require(
            BadgeInk(image: image, scale: scale, fill: .init(red: fill.red, green: fill.green, blue: fill.blue)),
            "\(name): no number or letter drawn"
        )
        let pixel = 1 / scale
        #expect(
            abs(ink.gap.dx) <= Self.largestGap,
            "\(name): the ink is \(format(ink.gap.dx)) pt off the centre of the badge, across"
        )
        #expect(
            abs(ink.gap.dy) <= Self.largestGap,
            "\(name): the ink is \(format(ink.gap.dy)) pt off the centre of the badge, down"
        )
        #expect(
            abs(ink.badge.width - diameter) <= 2 * pixel && abs(ink.badge.height - diameter) <= 2 * pixel,
            "\(name): the badge is \(format(ink.badge.width)) x \(format(ink.badge.height)) pt"
        )
        if line.mode == .metro {
            #expect(
                abs(ink.badge.width - ink.badge.height) <= pixel,
                "\(name): not a circle, \(format(ink.badge.width)) x \(format(ink.badge.height)) pt"
            )
        }
        #expect(
            ink.margin >= diameter * 0.05,
            "\(name): the ink comes \(format(ink.margin)) pt from the edge of the badge"
        )
        let colourGap = [
            ink.inkColour.red - text.red, ink.inkColour.green - text.green, ink.inkColour.blue - text.blue
        ].map(abs).max() ?? 1
        #expect(
            colourGap <= 0.06,
            "\(name): the ink is #\(ink.inkColour.hex), the text colour of the line is #\(line.color?.text ?? "")"
        )
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    static func everyLine() throws -> [TransitLine] {
        var seen = Set<String>()
        var lines: [TransitLine] = []
        for station in try StationCatalog.bundled().stations {
            for line in station.lines where seen.insert(line.displayName).inserted {
                lines.append(line)
            }
        }
        return lines.sorted { left, right in
            if left.mode != right.mode { return left.mode == .metro }
            let leftNumber = Int(left.name.prefix { $0.isNumber }) ?? 0
            let rightNumber = Int(right.name.prefix { $0.isNumber }) ?? 0
            if leftNumber != rightNumber { return leftNumber < rightNumber }
            return left.name < right.name
        }
    }
}
