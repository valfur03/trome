import SwiftUI

struct DrawnText: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isTruncated: Bool
    let visibleCharacters: Int

    init?(_ layout: Text.Layout, at origin: CGPoint) {
        guard let bounds = layout.map(\.typographicBounds.rect).reduce(nil, Self.union) else { return nil }
        let frame = bounds.offsetBy(dx: origin.x, dy: origin.y)
        x = frame.minX
        y = frame.minY
        width = frame.width
        height = frame.height
        isTruncated = layout.isTruncated
        let glyphs = layout.flatMap { line in line.flatMap(\.characterIndices) }
        visibleCharacters = Set(isTruncated ? glyphs.dropLast() : glyphs[...]).count
    }

    private static func union(_ rect: CGRect?, _ other: CGRect) -> CGRect {
        rect.map { $0.union(other) } ?? other
    }
}

@MainActor
final class DrawnTextRecorder {
    private(set) var texts: [DrawnText] = []

    func reset() {
        texts = []
    }

    func record(_ layouts: Text.LayoutKey.Value, in proxy: GeometryProxy) -> Color {
        texts = layouts.compactMap { DrawnText($0.layout, at: proxy[$0.origin]) }
        return .clear
    }
}
