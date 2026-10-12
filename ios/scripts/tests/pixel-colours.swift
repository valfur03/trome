// Prints the colour of some pixels of a picture, one per line, as RRGGBB (x right, y down, from the top left).
// Usage: pixel-colours <png> <x,y>...
//
// It reads the pixels that the picture shows, not the code that drew them.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
let points = arguments.dropFirst(2).map { $0.split(separator: ",").compactMap { Int($0) } }
guard arguments.count >= 3, points.allSatisfy({ $0.count == 2 }) else {
    FileHandle.standardError.write(Data("Usage: pixel-colours <png> <x,y>...\n".utf8))
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("Cannot read the picture \(arguments[1])\n".utf8))
    exit(1)
}
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))   // the bitmap rows run from the top
for point in points {
    let (x, y) = (point[0], point[1])
    guard (0..<w).contains(x), (0..<h).contains(y) else {
        FileHandle.standardError.write(Data("The point \(x),\(y) is outside the picture of \(w) x \(h)\n".utf8))
        exit(1)
    }
    let i = (y * w + x) * 4
    print(String(format: "%02X%02X%02X", pixels[i], pixels[i + 1], pixels[i + 2]))
}
