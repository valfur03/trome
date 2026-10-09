import SwiftUI
import TROMECore

/// The badge of a metro or RER line: a circle for the metro, a rounded square for the RER, in the official colours of
/// the line, with its number or letter at the centre. Every surface draws this one view, at its own size, so the
/// digit keeps the same size against its badge everywhere.
public struct LineBadgeView: View {
    /// The corner radius of the RER square, as a share of its side.
    nonisolated static let rerCornerRatio: CGFloat = 0.21

    let line: TransitLine
    @ScaledMetric private var diameter: CGFloat
    private let scalesWithText: Bool
    private let fixedDiameter: CGFloat

    public init(line: TransitLine, surface: LineBadgeSurface) {
        self.line = line
        _diameter = ScaledMetric(wrappedValue: surface.diameter, relativeTo: surface.textStyle)
        scalesWithText = surface.scalesWithText
        fixedDiameter = surface.diameter
    }

    /// A badge of a given size, which does not follow the text size: for the tests.
    init(line: TransitLine, diameter: CGFloat) {
        self.line = line
        _diameter = ScaledMetric(wrappedValue: diameter)
        scalesWithText = false
        fixedDiameter = diameter
    }

    private var side: CGFloat {
        scalesWithText ? diameter : fixedDiameter
    }

    public var body: some View {
        LineBadgeLabel(name: line.name, mode: line.mode)
            .fill(line.badgeTextColor)
            .background(line.badgeColor, in: shape)
            .frame(width: side, height: side)
            .alignmentGuide(.firstTextBaseline) { $0.height * Self.baselineRatio }
            .alignmentGuide(.lastTextBaseline) { $0.height * Self.baselineRatio }
    }

    /// The baseline of the number or letter, from the top of the badge, as a share of its height: a row that aligns
    /// its texts by their baseline puts the digit on the line of its text.
    nonisolated static let baselineRatio = 0.5 + LineBadgeLabel.capHeightRatio / 2

    private var shape: AnyShape {
        switch line.mode {
        case .metro: AnyShape(Circle())
        case .rer: AnyShape(RoundedRectangle(cornerRadius: side * Self.rerCornerRatio))
        }
    }
}
