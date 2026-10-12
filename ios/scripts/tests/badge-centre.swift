// Measures where the label of a round line badge sits in a picture: the centre of the weight of its ink, against the
// centre of the circle, in pixels and in percent of the diameter (x right, y down), and the centre of the box of its
// pixels that are at least half ink, in pixels, and the room between those pixels and the edge of the circle.
// Usage: badge-centre <png> <centre x> <centre y> <diameter> <ink colour, hex RRGGBB>
//
// It reads the pixels that the picture shows, not the code that drew them: each pixel inside the circle counts as
// much ink as its colour is near the ink colour, from the colour of the badge (read above the label) to the ink.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 6, let cx = Double(arguments[2]), let cy = Double(arguments[3]),
      let diameter = Double(arguments[4]), let inkHex = UInt32(arguments[5], radix: 16) else {
    FileHandle.standardError.write(Data("Usage: badge-centre <png> <centre x> <centre y> <diameter> <ink RRGGBB>\n".utf8))
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("Cannot read the picture \(arguments[1])\n".utf8))
    exit(1)
}
let width = image.width, height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { bytes in
    let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}
func colour(_ x: Int, _ y: Int) -> [Double] {   // y from the top: the rows of the bitmap
    let i = (y * width + x) * 4
    return [Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2])]
}
let ink = [Double((inkHex >> 16) & 0xFF), Double((inkHex >> 8) & 0xFF), Double(inkHex & 0xFF)]
// The colour of the badge: a pixel inside the circle, above the label (a label is under half the diameter tall).
let badge = colour(Int(cx), Int(cy - 0.4 * diameter))
let span = zip(ink, badge).map { $0 - $1 }
let spanSquared = span.reduce(0) { $0 + $1 * $1 }
guard spanSquared > 0 else {
    FileHandle.standardError.write(Data("The ink and the badge have the same colour\n".utf8))
    exit(1)
}
// Inside the circle, away from its smoothed edge.
let radius = diameter / 2 - 3
var total = 0.0, sumX = 0.0, sumY = 0.0
var box = (minX: Int.max, maxX: Int.min, minY: Int.max, maxY: Int.min)   // the pixels at least half covered
var reach = 0.0   // the farthest corner of those pixels from the centre
for y in Int(cy - radius)...Int(cy + radius) {
    for x in Int(cx - radius)...Int(cx + radius) {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        guard (px - cx) * (px - cx) + (py - cy) * (py - cy) <= radius * radius else { continue }
        let c = colour(x, y)
        let along = zip(zip(c, badge).map { $0 - $1 }, span).reduce(0) { $0 + $1.0 * $1.1 } / spanSquared
        let weight = min(1, max(0, along))
        total += weight
        sumX += weight * px
        sumY += weight * py
        if weight >= 0.5 {
            box = (min(box.minX, x), max(box.maxX, x), min(box.minY, y), max(box.maxY, y))
            reach = max(reach, ((abs(px - cx) + 0.5) * (abs(px - cx) + 0.5) + (abs(py - cy) + 0.5) * (abs(py - cy) + 0.5)).squareRoot())
        }
    }
}
guard total > 0 else {
    FileHandle.standardError.write(Data("No ink in the badge\n".utf8))
    exit(1)
}
let dx = sumX / total - cx, dy = sumY / total - cy
let bx = Double(box.minX + box.maxX + 1) / 2 - cx, by = Double(box.minY + box.maxY + 1) / 2 - cy
print(String(format: "weight x %+.2f px %+.2f %%, y %+.2f px %+.2f %%; box x %+.1f px, y %+.1f px; edge room %.1f %%",
             dx, 100 * dx / diameter, dy, 100 * dy / diameter, bx, by, 100 * (diameter / 2 - reach) / diameter))
