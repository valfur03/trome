import CoreText
import Synchronization
import SwiftUI
import TROMECore

/// The number or letter of a line badge, drawn as the outlines of its glyphs and centred by its ink.
///
/// A `Text` centres its line box, not what it draws: the box of a digit holds room for accents and descenders, and
/// the side bearings of a glyph are not equal, so a digit drawn by a `Text` sits off the centre of its badge.
/// This shape takes the outlines of the bold system font and places what they draw, at any size and on every surface.
/// A metro number goes by the weight of its ink across and by its box down (`LabelInk`); an RER letter goes by its box
/// on both axes, which already looks centred, as on the signs.
struct LineBadgeLabel: Shape {
    /// The height of a digit or a capital letter, as a share of the badge height.
    static let capHeightRatio: CGFloat = 0.44
    /// The room between the box of the ink and the edge of the badge that sets the size of a long label, as a share
    /// of the badge height.
    static let marginRatio: CGFloat = 0.1
    /// The smallest room between the ink and the edge of a metro badge, as a share of the badge height: a number
    /// that its weight moves nearer the edge gets smaller, by the least that keeps this room.
    static let edgeMarginRatio: CGFloat = 0.05
    /// The size of "bis" against the size of its number.
    static let bisScale: CGFloat = 0.55
    static let bis = "bis"

    let name: String
    let mode: TransitMode

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard side > 0 else { return Path() }
        let glyphs = Self.glyphs(of: name, side: side)
        let bounds = glyphs.boundingBoxOfPath
        guard !bounds.isEmpty else { return Path() }
        var scale = fitScale(of: bounds.size, side: side)
        var anchor = CGPoint(x: bounds.midX, y: bounds.midY)
        if mode == .metro, let ink = Self.ink(of: name, side: side, glyphs: glyphs) {
            anchor = ink.anchor
            scale = min(scale, side * (0.5 - Self.edgeMarginRatio) / ink.reach)
        }
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -anchor.x, y: -anchor.y)
        guard let placed = glyphs.copy(using: &transform) else { return Path() }
        return Path(placed)
    }

    /// The weight of a label is measured once for each name and size: a badge draws its path at each layout.
    private static let inks = Mutex<[InkKey: LabelInk]>([:])

    private struct InkKey: Hashable {
        let name: String
        let side: CGFloat
    }

    private static func ink(of name: String, side: CGFloat, glyphs: CGPath) -> LabelInk? {
        let key = InkKey(name: name, side: side)
        if let known = inks.withLock({ $0[key] }) { return known }
        guard let ink = LabelInk(of: glyphs) else { return nil }
        inks.withLock { $0[key] = ink }
        return ink
    }

    /// The size of a label: it shrinks when the box of its ink would come nearer to the edge than the margin, so
    /// that the corners of the box stay inside a circle, or inside a square, smaller than the badge by the margin.
    private func fitScale(of size: CGSize, side: CGFloat) -> CGFloat {
        let room = side * (1 - 2 * Self.marginRatio)
        let fit: CGFloat
        switch mode {
        case .metro:
            fit = room / (size.width * size.width + size.height * size.height).squareRoot()
        case .rer:
            fit = room / max(size.width, size.height)
        }
        return min(1, fit)
    }

    /// The outlines of the name, in the units of CoreText (y up), with its main glyphs at the cap height of the
    /// badge. A name that ends with "bis" draws it smaller, on the same baseline.
    static func glyphs(of name: String, side: CGFloat) -> CGPath {
        let main = name.hasSuffix(bis) ? String(name.dropLast(bis.count)) : name
        let probe = font(size: 100)
        let fontSize = 100 * side * capHeightRatio / CTFontGetCapHeight(probe)
        let path = CGMutablePath()
        let mainFont = font(size: fontSize)
        let mainWidth = append(main, font: mainFont, at: 0, to: path)
        if main != name {
            let bisFont = font(size: fontSize * bisScale)
            _ = append(bis, font: bisFont, at: mainWidth + fontSize * 0.04, to: path)
        }
        return path
    }

    static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    /// Adds the outlines of a text, with its baseline at y = 0 and its origin at the offset, and returns its advance.
    private static func append(_ text: String, font: CTFont, at offset: CGFloat, to path: CGMutablePath) -> CGFloat {
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                guard let outline = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                let move = CGAffineTransform(translationX: offset + positions[index].x, y: positions[index].y)
                path.addPath(outline, transform: move)
            }
        }
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
}
