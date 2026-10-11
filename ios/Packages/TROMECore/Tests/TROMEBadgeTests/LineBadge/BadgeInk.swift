import CoreGraphics

/// Measures a drawn line badge in an image with a clear background: the box of the badge (every pixel that is not
/// clear), the box of the ink of its number or letter (the pixels far from the badge colour), the centre of the
/// weight of that ink (what the eye reads as its middle), the colour of the ink, and how near it comes to the edge.
struct BadgeInk {
    struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        var hex: String {
            [red, green, blue].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        }
    }

    /// The badge box and the ink box, in points.
    let badge: CGRect
    let ink: CGRect
    /// The centre of the badge, from all that it covers (the badge is symmetric), and the centre of the weight of
    /// the ink, each pixel counted by how much of it the ink covers; within a small part of a pixel, in points.
    let badgeCentre: CGPoint
    let weightCentre: CGPoint
    /// The colour of the ink as drawn, from the pixels at its core (away from the smoothed edges).
    let inkColour: RGB
    /// The smallest distance from the ink to the edge of the badge, in points.
    let margin: CGFloat

    var gap: CGVector {
        CGVector(dx: ink.midX - badge.midX, dy: ink.midY - badge.midY)
    }

    /// How far the centre of the weight of the ink is from the centre of the badge, across.
    var weightGap: CGFloat {
        weightCentre.x - badgeCentre.x
    }

    init?(image: CGImage, scale: CGFloat, fill: RGB) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let measure = Self.distances(of: pixels, width: width, height: height, from: fill)
        // The ink is every pixel at least half as far from the badge colour as the farthest pixel.
        guard measure.farthest > 40, let badgeRect = measure.badge.rect(scale: scale) else { return nil }
        var inkBox = PixelBox()
        var core = (red: 0.0, green: 0.0, blue: 0.0, count: 0.0)
        var isInk = [Bool](repeating: false, count: width * height)
        var weight = (total: 0.0, x: 0.0, y: 0.0)
        for index in 0..<(width * height) where measure.distances[index] > 0 {
            let share = min(1, measure.distances[index] / measure.farthest)
            weight.total += share
            weight.x += share * (Double(index % width) + 0.5)
            weight.y += share * (Double(index / width) + 0.5)
        }
        for index in 0..<(width * height) where measure.distances[index] >= measure.farthest / 2 {
            inkBox.add(index % width, index / width)
            isInk[index] = true
            if measure.distances[index] >= measure.farthest * 0.9 {
                let alpha = Double(pixels[index * 4 + 3])
                core.red += Double(pixels[index * 4]) / alpha
                core.green += Double(pixels[index * 4 + 1]) / alpha
                core.blue += Double(pixels[index * 4 + 2]) / alpha
                core.count += 1
            }
        }
        guard let inkRect = inkBox.rect(scale: scale) else { return nil }
        badge = badgeRect
        ink = inkRect
        badgeCentre = Self.centre(of: pixels, width: width, height: height, scale: scale)
        weightCentre = CGPoint(x: weight.x / weight.total / scale, y: weight.y / weight.total / scale)
        inkColour = RGB(red: core.red / core.count, green: core.green / core.count, blue: core.blue / core.count)
        let inside = measure.distances.map { $0 >= 0 }
        margin = Self.margin(of: isInk, inside: inside, width: width, height: height) / scale
    }

    /// The centre of all that is drawn, each pixel counted by its opacity.
    private static func centre(of pixels: [UInt8], width: Int, height: Int, scale: CGFloat) -> CGPoint {
        var total = 0.0
        var sumX = 0.0
        var sumY = 0.0
        for row in 0..<height {
            for column in 0..<width {
                let alpha = Double(pixels[(row * width + column) * 4 + 3])
                total += alpha
                sumX += alpha * (Double(column) + 0.5)
                sumY += alpha * (Double(row) + 0.5)
            }
        }
        return CGPoint(x: sumX / total / scale, y: sumY / total / scale)
    }

    /// The distance of each pixel from the badge colour: -1 outside the badge, 0 on its smoothed edge.
    private struct Distances {
        let distances: [Double]
        let farthest: Double
        let badge: PixelBox
    }

    private static func distances(of pixels: [UInt8], width: Int, height: Int, from fill: RGB) -> Distances {
        let fillColour = (fill.red * 255, fill.green * 255, fill.blue * 255)
        var distances = [Double](repeating: -1, count: width * height)
        var badgeBox = PixelBox()
        var farthest = 0.0
        pixels.withUnsafeBufferPointer { pixels in
            distances.withUnsafeMutableBufferPointer { distances in
                for row in 0..<height {
                    for column in 0..<width {
                        let index = row * width + column
                        let alpha = Double(pixels[index * 4 + 3])
                        guard alpha >= 128 else { continue }
                        badgeBox.add(column, row)
                        guard alpha >= 250 else {
                            distances[index] = 0
                            continue
                        }
                        let red = Double(pixels[index * 4]) * 255 / alpha - fillColour.0
                        let green = Double(pixels[index * 4 + 1]) * 255 / alpha - fillColour.1
                        let blue = Double(pixels[index * 4 + 2]) * 255 / alpha - fillColour.2
                        let distance = (red * red + green * green + blue * blue).squareRoot()
                        distances[index] = distance
                        farthest = max(farthest, distance)
                    }
                }
            }
        }
        return Distances(distances: distances, farthest: farthest, badge: badgeBox)
    }

    /// The distance from the nearest ink pixel to the nearest pixel outside the badge (the border of the image
    /// counts as outside), by a chamfer distance map: two passes over the image, within about 8% of the true distance.
    private static func margin(of isInk: [Bool], inside: [Bool], width: Int, height: Int) -> CGFloat {
        let paddedWidth = width + 2
        let paddedHeight = height + 2
        let far = Double.greatestFiniteMagnitude / 2
        var distance = [Double](repeating: 0, count: paddedWidth * paddedHeight)
        for row in 0..<height {
            for column in 0..<width where inside[row * width + column] {
                distance[(row + 1) * paddedWidth + column + 1] = far
            }
        }
        let diagonal = 2.0.squareRoot()
        distance.withUnsafeMutableBufferPointer { map in
            for row in 1..<(paddedHeight - 1) {
                for column in 1..<(paddedWidth - 1) {
                    let index = row * paddedWidth + column
                    let above = index - paddedWidth
                    let corners = min(map[above - 1], map[above + 1]) + diagonal
                    let sides = min(map[above], map[index - 1]) + 1
                    map[index] = min(map[index], min(corners, sides))
                }
            }
            for row in stride(from: paddedHeight - 2, through: 1, by: -1) {
                for column in stride(from: paddedWidth - 2, through: 1, by: -1) {
                    let index = row * paddedWidth + column
                    let below = index + paddedWidth
                    let corners = min(map[below - 1], map[below + 1]) + diagonal
                    let sides = min(map[below], map[index + 1]) + 1
                    map[index] = min(map[index], min(corners, sides))
                }
            }
        }
        var nearest = far
        for row in 0..<height {
            for column in 0..<width where isInk[row * width + column] {
                nearest = min(nearest, distance[(row + 1) * paddedWidth + column + 1])
            }
        }
        return CGFloat(nearest)
    }
}

private struct PixelBox {
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min

    mutating func add(_ column: Int, _ row: Int) {
        minX = min(minX, column)
        minY = min(minY, row)
        maxX = max(maxX, column)
        maxY = max(maxY, row)
    }

    func rect(scale: CGFloat) -> CGRect? {
        guard minX <= maxX else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }
}
