import CoreGraphics

/// Where a line number goes in its badge so that it looks centred: the centre of the weight of its ink across, and
/// the middle of its box down.
///
/// The eye reads where the ink is heavy, not where its box ends. The flag of a 1 widens the box to the left with
/// little ink, so a 11 centred by its box sits to the right; a big 3 with a small "bis" sits to the left. Down, the
/// box keeps every digit at the same cap height and on the same baseline, as signs do.
///
/// The weight is measured on the filled drawing of the outlines, not by a formula on them: the outlines of a glyph
/// may overlap, and a formula would count the overlap twice. This file uses CoreGraphics only, so that a tool outside
/// the app can compile it and place its badges by the same rule.
struct LabelInk {
    /// The point of the outlines that goes on the centre of the badge.
    let anchor: CGPoint
    /// The farthest that the ink goes from the anchor.
    let reach: CGFloat

    /// The longer side of the drawing that measures the weight, in pixels: the centre is then within a thousandth
    /// of the width of the label.
    static let resolution: CGFloat = 512

    /// Measures filled outlines (y up). Nil for outlines with no ink.
    init?(of path: CGPath) {
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let pixel = max(bounds.width, bounds.height) / Self.resolution
        let width = Int((bounds.width / pixel).rounded(.up)) + 2
        let height = Int((bounds.height / pixel).rounded(.up)) + 2
        // One pixel of room on each side: pixel (column, row) starts at origin + column, and row 0 is the top.
        let origin = CGPoint(x: bounds.minX - pixel, y: bounds.minY - pixel)
        var coverage = [UInt8](repeating: 0, count: width * height)
        let drawn = coverage.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.scaleBy(x: 1 / pixel, y: 1 / pixel)
            context.translateBy(x: -origin.x, y: -origin.y)
            context.addPath(path)
            context.setFillColor(gray: 1, alpha: 1)
            context.fillPath()
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        var sumX = 0.0
        for row in 0..<height {
            for column in 0..<width {
                let value = Double(coverage[row * width + column])
                total += value
                sumX += value * (Double(column) + 0.5)
            }
        }
        guard total > 0 else { return nil }
        let anchor = CGPoint(x: origin.x + CGFloat(sumX / total) * pixel, y: bounds.midY)
        // The farthest pixel that is at least half covered, to its far corner.
        var farthest: CGFloat = 0
        for row in 0..<height {
            let down = origin.y + (CGFloat(height - 1 - row) + 0.5) * pixel - anchor.y
            for column in 0..<width where coverage[row * width + column] >= 128 {
                let across = origin.x + (CGFloat(column) + 0.5) * pixel - anchor.x
                farthest = max(farthest, across * across + down * down)
            }
        }
        self.anchor = anchor
        reach = farthest.squareRoot() + pixel / 2.squareRoot()
    }
}
