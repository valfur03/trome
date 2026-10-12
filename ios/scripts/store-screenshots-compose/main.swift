// Composes the four store pictures of one language from the captures of the Simulator.
// Usage: store-screenshots-compose <captures dir> <out dir> <language> <bezel png or ""> <pictograms|dots>
// It builds with LabelInk.swift of the app (make store-screenshots-compose), so that its line badge follows the same rule.
//
// The first three pictures are one panorama, cut in three: one lit field, one line drawing whose stroke takes the
// colour of the next line at each border, like a transfer. Each has the lock screen cut off the top edge (the
// Live Activity card, the home bar), a headline, the line, and the Dynamic Island cut by the bottom edge.
// The fourth goes on with the same field, but its phone is cut by the bottom edge instead: the app screen is shorter
// than the phone, so its top (the name, the rows, the two links) is the part that shows, under the headline, and the
// picture ends just under the link Help and feedback, before the footer. The line goes behind that phone.
// The captures are real: drawn in their pixels, at one scale, never stretched, never redrawn.
// With a bezel file (Apple's iPhone bezel, a PNG with a transparent screen), each cut is in it, straight and
// unchanged, and the square corners of the captures are cut to its round screen; with none, or one that does not
// fit the captures, the cuts have rounded corners and no frame.
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 6, ["pictograms", "dots"].contains(arguments[5]) else {
    FileHandle.standardError.write(Data(
        "Usage: store-screenshots-compose <captures dir> <out dir> <language> <bezel png or \"\"> <pictograms|dots>\n".utf8
    ))
    exit(2)
}
let capturesDir = arguments[1], outDir = arguments[2], language = arguments[3], bezelPath = arguments[4]
let showsPictograms = arguments[5] == "pictograms"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

// MARK: The set

enum Pictogram: CaseIterable {
    case coffee, headphones, book, bag, umbrella, music, bike, sun, briefcase, camera, glasses
}

struct Picture {
    let name: String
    let line: UInt32           // the official colour of the line
    let badge: String?         // the line badge; none on the picture of the app
    let square: Bool           // RER: a rounded square; metro: round
    let badgeInk: UInt32
    let headlines: [String: String]
    let stops: [Pictogram]     // the stops of the line, left to right; none on the picture of the app
}

let pictures = [
    Picture(name: "metro", line: 0x6E491E, badge: "11", square: false, badgeInk: 0xFFFFFF,
            headlines: ["en": "Your next trains, on your lock screen.", "fr": "Vos prochains trains, sur l’écran verrouillé."],
            stops: [.coffee, .headphones, .book]),
    Picture(name: "fork", line: 0xFF82B4, badge: "7", square: false, badgeInk: 0x000000,
            headlines: ["en": "Every direction, even at a fork.", "fr": "Toutes les directions, même à une bifurcation."],
            stops: [.bag, .umbrella, .music]),
    Picture(name: "rer", line: 0x5091CB, badge: "B", square: true, badgeInk: 0xFFFFFF,
            headlines: ["en": "Your RER, minute by minute.", "fr": "Votre RER, minute par minute."],
            stops: [.briefcase, .camera, .glasses]),
    Picture(name: "app", line: 0x2A3BC0, badge: nil, square: false, badgeInk: 0xFFFFFF,
            headlines: ["en": "One screen, set once.", "fr": "Un seul écran, réglé une fois."],
            stops: []),
]
let branchStops: [Pictogram] = [.bike, .sun]   // the two stops of the branch of the fork
let linePictures = 3   // the line runs across the first three; it goes behind the phone of the app, so none of it shows there

// MARK: Sizes (pixels of a picture of 1320 x 2868, the 6.9-inch size of the store)

let pic = CGSize(width: 1320, height: 2868)
let W = pic.width * CGFloat(pictures.count), H = pic.height
let captureSize = CGSize(width: 1206, height: 2622)    // the iPhone 17 Simulator
let lockBottom: CGFloat = 1489     // where the lock screen cut ends (the bottom of the screen, or of the phone)
let textTop: CGFloat = 1689, lineY: CGFloat = 2194
let islandRows: CGFloat = 230      // the rows of the capture that the island cut shows: the status bar and the island
let islandTop: CGFloat = 2414      // with no bezel: the strip floats over the field
let appCutMargin: CGFloat = 64     // the rows of the app screen shown under the link Help and feedback: its card ends
let appTextGap: CGFloat = 80       // the least room above and under the headline of the app picture
let side: CGFloat = 57, corner: CGFloat = 64
let maxFontSize: CGFloat = 132, lineStep: CGFloat = 1.08, textWidth: CGFloat = 1220
let night: UInt32 = 0x05060D

// MARK: Colours

struct RGB { var r, g, b: CGFloat }
func rgb(_ hex: UInt32) -> RGB {
    RGB(r: CGFloat((hex >> 16) & 0xFF) / 255, g: CGFloat((hex >> 8) & 0xFF) / 255, b: CGFloat(hex & 0xFF) / 255)
}
func cg(_ c: RGB, _ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }
func hsl(_ c: RGB, saturation: CGFloat, lightness: CGFloat) -> RGB {
    let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b), delta = maxC - minC
    var hue: CGFloat = 0
    if delta > 0 {
        if maxC == c.r {
            hue = ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == c.g {
            hue = (c.b - c.r) / delta + 2
        } else {
            hue = (c.r - c.g) / delta + 4
        }
    }
    hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
    let chroma = (1 - abs(2 * lightness - 1)) * saturation
    let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1)), m = lightness - chroma / 2
    let (r, g, b): (CGFloat, CGFloat, CGFloat) = switch hue {
    case ..<60: (chroma, x, 0)
    case ..<120: (x, chroma, 0)
    case ..<180: (0, chroma, x)
    case ..<240: (0, x, chroma)
    case ..<300: (x, 0, chroma)
    default: (chroma, 0, x)
    }
    return RGB(r: r + m, g: g + m, b: b + m)
}
struct Palette { let line, field, glow, stroke, accent, ink: RGB }
let palettes = pictures.map { p -> Palette in
    let l = rgb(p.line)
    return Palette(line: l,
                   field: hsl(l, saturation: 0.70, lightness: 0.25),   // the lit field
                   glow: hsl(l, saturation: 0.78, lightness: 0.52),    // the light behind the headline
                   stroke: hsl(l, saturation: 0.90, lightness: 0.62),  // the line drawing
                   accent: hsl(l, saturation: 0.90, lightness: 0.80),  // the headline after the comma
                   ink: hsl(l, saturation: 0.85, lightness: 0.40))     // the pictograms, on white
}
let base = rgb(night), white = RGB(r: 1, g: 1, b: 1)

// MARK: Files

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Cannot read the picture \(path)") }
    return image
}
func capture(_ name: String) -> CGImage {
    let path = "\(capturesDir)/\(name)-\(language).png"
    let image = load(path)
    guard CGFloat(image.width) == captureSize.width, CGFloat(image.height) == captureSize.height else {
        fail("\(path) is \(image.width) x \(image.height), not a capture of the iPhone 17 Simulator (1206 x 2622)")
    }
    return image
}
/// The last row of the capture that the link Help and feedback covers.
func helpRowBottom() -> CGFloat {
    let path = "\(capturesDir)/app-help-row-\(language).txt"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let bottom = text.split(whereSeparator: \.isWhitespace).dropFirst().first.flatMap({ Double($0) }) else {
        fail("Cannot read \(path)")
    }
    return CGFloat(bottom)
}
func write(_ image: CGImage, _ path: String) {
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else {
        fail("Cannot write \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(path)") }
}

// MARK: The bezel: its screen and its scale

/// Apple's bezel, measured: the box of its opaque pixels, and the transparent screen in its middle.
struct Bezel {
    let image: CGImage
    let body: CGRect      // the opaque pixels, in the pixels of the file
    let screen: CGRect    // the transparent screen
    let screenCorner: CGFloat   // the radius of its corners, a little short, so the frame always covers the capture
    let scale: CGFloat    // the scale of the file in the picture: 1, or less so that the whole body width shows
    var captureScale: CGFloat { scale * screen.width / captureSize.width }

    /// The rect of the whole file in the picture, for a screen drawn at `screenRect`.
    func frame(around screenRect: CGRect) -> CGRect {
        CGRect(x: screenRect.minX - screen.minX * scale, y: screenRect.minY - screen.minY * scale,
               width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }
    var bottom: CGFloat { (body.maxY - screen.maxY) * scale }   // from the screen to the bottom of the body
    var top: CGFloat { (screen.minY - body.minY) * scale }      // from the top of the body to the screen
    /// The capture, cut to the screen: its square corners would show past the round corners of the frame.
    func screenShape(_ screenRect: CGRect) -> CGPath {
        CGPath(roundedRect: screenRect, cornerWidth: screenCorner * scale, cornerHeight: screenCorner * scale, transform: nil)
    }
}

enum BezelResult { case fits(Bezel), none(String) }

func measureBezel(_ path: String) -> BezelResult {
    guard !path.isEmpty else { return .none("no bezel file was given") }
    guard FileManager.default.fileExists(atPath: path) else { return .none("there is no bezel file at \(path)") }
    let image = load(path)
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let alphaContext = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    alphaContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * w + x) * 4 + 3] }   // y from the top: the bitmap rows
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h {
        for x in 0..<w where alpha(x, y) > 16 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX > minX, maxY > minY else { return .none("the bezel file \(path) has no opaque pixel") }
    let body = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    // The screen: walk out from the middle until the frame. The column is at a quarter of the width,
    // away from the island at the top of the screen.
    let midY = Int(body.midY), quarterX = Int(body.minX + body.width / 4), midX = Int(body.midX)
    guard alpha(midX, midY) < 16 else { return .none("the bezel file \(path) has no transparent screen in its middle") }
    var left = midX, right = midX, top = midY, bottom = midY
    while left > 0, alpha(left - 1, midY) < 128 { left -= 1 }
    while right < w - 1, alpha(right + 1, midY) < 128 { right += 1 }
    while top > 0, alpha(quarterX, top - 1) < 128 { top -= 1 }
    while bottom < h - 1, alpha(quarterX, bottom + 1) < 128 { bottom += 1 }
    let screen = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    // The corner: on the diagonal in from the top-left corner of the screen box, the screen starts after the last
    // opaque pixel of the frame (the box corner itself is outside the round body). On a round corner of radius r,
    // that is r (1 - 1/√2) from the corner on each side.
    let diagonal = ((0..<Int(screen.width / 4)).last { alpha(left + $0, top + $0) >= 128 }).map { $0 + 1 } ?? 0
    let screenCorner = CGFloat(max(0, diagonal - 3)) / (1 - 1 / 2.squareRoot())
    let ratio = (screen.height / screen.width) / (captureSize.height / captureSize.width)
    guard abs(ratio - 1) < 0.015 else {
        return .none(String(format: "the screen of the bezel is %d x %d, not the shape of the captures (1206 x 2622)",
                            Int(screen.width), Int(screen.height)))
    }
    let scale = min(1, pic.width / body.width)
    let bezel = Bezel(image: image, body: body, screen: screen, screenCorner: screenCorner, scale: scale)
    guard bezel.captureScale >= 0.9, bezel.captureScale <= 1.15 else {
        return .none(String(format: "with the whole bezel in the width, the captures would be at scale %.3f (0.9 to 1.15 allowed)",
                            bezel.captureScale))
    }
    return .fits(bezel)
}

let bezelResult = measureBezel(bezelPath)
let bezel: Bezel? = if case .fits(let b) = bezelResult { b } else { nil }
let captureScale = bezel?.captureScale ?? 1

// MARK: The layout of the app picture: the phone cut by the bottom edge, the headline centred above it

let appLastRow = min(helpRowBottom() + appCutMargin, captureSize.height)   // the last row of the capture shown
let appScreenTop = H - appLastRow * captureScale
let appPhoneTop = appScreenTop - (bezel?.top ?? 0)
let appTextCentre = appPhoneTop / 2
guard appPhoneTop >= 2 * (maxFontSize * lineStep + appTextGap) else {
    fail("The app screen leaves no room for the headline: the phone starts at y \(Int(appPhoneTop))")
}

// MARK: The context: top-left origin, as the captures

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: H)
context.scaleBy(x: 1, y: -1)
context.interpolationQuality = .high

// MARK: The headlines: broken after the comma, the part after it in the accent colour

struct TextLine { let string: String; let accent: Bool }
func clauses(_ headline: String) -> [TextLine] {
    guard let comma = headline.firstIndex(of: ",") else { fail("A headline has no comma to break at: \(headline)") }
    return [TextLine(string: String(headline[...comma]), accent: false),
            TextLine(string: String(headline[headline.index(after: comma)...]).trimmingCharacters(in: .whitespaces), accent: true)]
}
func font(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .bold) }
func width(_ s: String, _ size: CGFloat) -> CGFloat {
    NSAttributedString(string: s, attributes: [.font: font(size)]).size().width
}
let headlines = pictures.map { p -> String in
    guard let h = p.headlines[language] else { fail("No headline in \(language) for the picture \(p.name)") }
    return h
}
// One size for the whole set of a language: the largest, up to 132, at which every line fits.
let fontSize = headlines.flatMap(clauses).map { min(maxFontSize, floor(maxFontSize * textWidth / width($0.string, maxFontSize))) }.min()!
let textHeight = 2 * fontSize * lineStep
func drawText(_ headline: String, palette: Palette, originX: CGFloat, top: CGFloat) {
    var y = top + (2 * maxFontSize * lineStep - textHeight) / 2   // a smaller size keeps the same centre
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    for t in clauses(headline) {
        let colour = t.accent ? NSColor(cgColor: cg(palette.accent))! : NSColor.white
        NSAttributedString(string: t.string, attributes: [.font: font(fontSize), .foregroundColor: colour])
            .draw(at: CGPoint(x: originX + (pic.width - width(t.string, fontSize)) / 2, y: y))
        y += fontSize * lineStep
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: The field: one sweep of the line colours, dark at the top, lit behind each headline

let blend: CGFloat = 260   // the half width of the colour change at each border
let textCentre = textTop + maxFontSize * lineStep
do {
    var colours: [CGColor] = [], locations: [CGFloat] = []
    for (i, p) in palettes.enumerated() {
        let start = CGFloat(i) * pic.width, end = start + pic.width
        colours += [cg(p.field), cg(p.field)]
        locations += [(i == 0 ? 0 : start + blend) / W, (i == palettes.count - 1 ? W : end - blend) / W]
    }
    let sweep = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: locations)!
    context.drawLinearGradient(sweep, start: .zero, end: CGPoint(x: W, y: 0), options: [])
    let shade = CGGradient(colorsSpace: space, colors: [cg(base, 0.8), cg(base, 0.5), cg(base, 0)] as CFArray,
                           locations: [0, 0.35, 1])!
    context.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 0, y: textCentre), options: [])
    context.saveGState()
    context.setBlendMode(.screen)
    for (i, p) in palettes.enumerated() {
        let centre = CGPoint(x: pic.width * (CGFloat(i) + 0.5), y: i == 3 ? appTextCentre : textCentre)
        let light = CGGradient(colorsSpace: space, colors: [cg(p.glow, 0.9), cg(p.glow, 0.36), cg(p.glow, 0)] as CFArray,
                               locations: [0, 0.45, 1])!
        context.drawRadialGradient(light, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 1350, options: [])
    }
    // The soft band of light along the line.
    for (i, p) in palettes.prefix(linePictures).enumerated() {
        let band = CGGradient(colorsSpace: space, colors: [cg(p.glow, 0.45), cg(p.glow, 0)] as CFArray, locations: [0, 1])!
        context.saveGState()
        context.translateBy(x: pic.width * (CGFloat(i) + 0.5), y: lineY)
        context.scaleBy(x: 850 / 150, y: 1)
        context.drawRadialGradient(band, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 150, options: [])
        context.restoreGState()
    }
    context.restoreGState()
}

// MARK: The line drawing (x in the panorama)

let strokeWidth: CGFloat = 40, dotRadius: CGFloat = 14, stopRadius: CGFloat = 40, pictogramSize: CGFloat = 52
let transferRadius: CGFloat = 46, transferRing: CGFloat = 13, badgeSize: CGFloat = 130
let badgeX: [CGFloat] = [150, pic.width + 250, 2 * pic.width + 250]
/// The least room between the ink of a metro number and the edge of its badge, as a share of the diameter, as in
/// the app.
let badgeEdgeMargin: CGFloat = 0.05
let stopX: [[CGFloat]] = [[470, 790, 1110], [560, 860, 1160], [560, 860, 1160]]
let trailHeads: [CGFloat] = [1000, 720, 1010]

func strokeLine(from x0: CGFloat, to x1: CGFloat, colour: RGB) {
    context.setStrokeColor(cg(colour))
    context.setLineWidth(strokeWidth)
    context.setLineCap(.butt)
    context.move(to: CGPoint(x: x0, y: lineY))
    context.addLine(to: CGPoint(x: x1, y: lineY))
    context.strokePath()
}
// The fork of picture 2: after its first station, a branch peels off at 45 degrees and ends at a terminus.
let forkFrom = pic.width + 560, forkDrop: CGFloat = 104, forkEnd = pic.width + 1200
let branchStopX: [CGFloat] = [pic.width + 860, pic.width + 1080]
do {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: forkFrom, y: lineY))
    p.addLine(to: CGPoint(x: forkFrom + forkDrop, y: lineY + forkDrop))
    p.addLine(to: CGPoint(x: forkEnd, y: lineY + forkDrop))
    context.addPath(p); context.setStrokeColor(cg(palettes[1].stroke)); context.setLineWidth(strokeWidth)
    context.setLineJoin(.round); context.setLineCap(.butt); context.strokePath()
}
for (i, p) in palettes.prefix(linePictures).enumerated() {
    strokeLine(from: i == 0 ? badgeX[0] : pic.width * CGFloat(i), to: pic.width * CGFloat(i + 1), colour: p.stroke)
}
// The light trail of a train going forward, with its small halo.
for (i, head) in trailHeads.enumerated() {
    let hx = pic.width * CGFloat(i) + head, tail = hx - 520
    context.saveGState()
    context.addRect(CGRect(x: tail, y: lineY - strokeWidth / 2, width: hx - tail, height: strokeWidth))
    context.clip()
    let trail = CGGradient(colorsSpace: space, colors: [cg(white, 0), cg(white, 0.85)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(trail, start: CGPoint(x: tail, y: lineY), end: CGPoint(x: hx, y: lineY), options: [])
    context.restoreGState()
    let halo = CGGradient(colorsSpace: space, colors: [cg(white, 0.9), cg(palettes[i].glow, 0.35), cg(palettes[i].glow, 0)] as CFArray,
                          locations: [0, 0.3, 1])!
    context.drawRadialGradient(halo, startCenter: CGPoint(x: hx, y: lineY), startRadius: 0,
                               endCenter: CGPoint(x: hx, y: lineY), endRadius: 70, options: [])
}
func terminus(at x: CGFloat, y: CGFloat) {   // a white bar across the stroke, as the end of a line on a map
    context.setFillColor(cg(white))
    context.fill(CGRect(x: x - 8, y: y - strokeWidth / 2 - 10, width: 16, height: strokeWidth + 20))
}
terminus(at: forkEnd, y: lineY + forkDrop)

// MARK: The pictograms: flat, drawn here in a box of 100 x 100, in one colour on the white stop

func drawPictogram(_ pictogram: Pictogram, centre: CGPoint, ink: RGB) {
    context.saveGState()
    context.translateBy(x: centre.x - pictogramSize / 2, y: centre.y - pictogramSize / 2)
    context.scaleBy(x: pictogramSize / 100, y: pictogramSize / 100)
    context.setFillColor(cg(ink)); context.setStrokeColor(cg(ink))
    context.setLineCap(.round); context.setLineJoin(.round)
    func fill(_ path: CGPath) { context.addPath(path); context.fillPath() }
    func stroke(_ path: CGPath, _ width: CGFloat) { context.setLineWidth(width); context.addPath(path); context.strokePath() }
    func knockOut(_ path: CGPath, _ width: CGFloat = 0) {   // white over the ink, as a gap
        context.saveGState(); context.setFillColor(cg(white)); context.setStrokeColor(cg(white))
        if width > 0 { stroke(path, width) } else { fill(path) }
        context.restoreGState()
    }
    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
    }
    func polyline(_ points: [(CGFloat, CGFloat)], closed: Bool = false) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        if closed { p.closeSubpath() }
        return p
    }
    func arc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, from a: CGFloat, to b: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: a * .pi / 180, endAngle: b * .pi / 180, clockwise: false)
        return p
    }
    switch pictogram {
    case .coffee:
        fill(rounded(16, 34, 52, 46, 12))
        stroke(circle(70, 52, 11), 8)
        fill(rounded(10, 84, 70, 8, 4))
        stroke(polyline([(32, 24), (32, 10)]), 7)
        stroke(polyline([(50, 24), (50, 10)]), 7)
    case .headphones:
        stroke(arc(50, 56, 34, from: 180, to: 360), 9)
        fill(rounded(10, 50, 20, 36, 8))
        fill(rounded(70, 50, 20, 36, 8))
    case .book:
        fill(polyline([(48, 26), (10, 18), (10, 78), (48, 86)], closed: true))
        fill(polyline([(52, 26), (90, 18), (90, 78), (52, 86)], closed: true))
    case .bag:
        fill(rounded(16, 38, 68, 52, 8))
        stroke(arc(50, 38, 15, from: 180, to: 360), 8)
    case .umbrella:
        let canopy = CGMutablePath()
        canopy.addArc(center: CGPoint(x: 50, y: 52), radius: 42, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        canopy.closeSubpath()
        fill(canopy)
        stroke(polyline([(50, 50), (50, 82)]), 8)
        stroke(arc(41, 82, 9, from: 0, to: 180), 8)
    case .music:
        fill(CGPath(ellipseIn: CGRect(x: 14, y: 66, width: 28, height: 22), transform: nil))
        fill(CGPath(ellipseIn: CGRect(x: 56, y: 58, width: 28, height: 22), transform: nil))
        stroke(polyline([(38, 76), (38, 22)]), 7)
        stroke(polyline([(80, 68), (80, 14)]), 7)
        fill(polyline([(35, 18), (83, 8), (83, 24), (35, 34)], closed: true))
    case .bike:
        stroke(circle(24, 66, 17), 7)
        stroke(circle(76, 66, 17), 7)
        stroke(polyline([(24, 66), (40, 40), (64, 40), (76, 66)]), 7)
        stroke(polyline([(40, 40), (50, 66), (64, 40)]), 7)
        stroke(polyline([(32, 30), (46, 30)]), 7)
        stroke(polyline([(64, 40), (60, 26), (70, 26)]), 7)
    case .sun:
        fill(circle(50, 50, 19))
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4
            stroke(polyline([(50 + 29 * cos(a), 50 + 29 * sin(a)), (50 + 42 * cos(a), 50 + 42 * sin(a))]), 8)
        }
    case .briefcase:
        stroke(rounded(36, 20, 28, 20, 6), 8)
        fill(rounded(10, 32, 80, 54, 9))
        knockOut(polyline([(10, 54), (90, 54)]), 5)
    case .camera:
        fill(rounded(34, 20, 32, 16, 5))
        fill(rounded(8, 30, 84, 56, 11))
        knockOut(circle(50, 58, 19))
        fill(circle(50, 58, 11))
    case .glasses:
        stroke(circle(28, 58, 16), 8)
        stroke(circle(72, 58, 16), 8)
        stroke(arc(50, 58, 7, from: 180, to: 360), 7)
        stroke(polyline([(12, 54), (6, 36)]), 7)
        stroke(polyline([(88, 54), (94, 36)]), 7)
    }
    context.restoreGState()
}

func drawStop(at centre: CGPoint, pictogram: Pictogram, palette: Palette) {
    context.setFillColor(cg(white))
    if showsPictograms {
        context.fillEllipse(in: CGRect(x: centre.x - stopRadius, y: centre.y - stopRadius, width: 2 * stopRadius, height: 2 * stopRadius))
        drawPictogram(pictogram, centre: centre, ink: palette.ink)
    } else {
        context.fillEllipse(in: CGRect(x: centre.x - dotRadius, y: centre.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
    }
}
for (i, xs) in stopX.enumerated() {
    for (k, local) in xs.enumerated() {
        drawStop(at: CGPoint(x: pic.width * CGFloat(i) + local, y: lineY), pictogram: pictures[i].stops[k], palette: palettes[i])
    }
}
for (k, x) in branchStopX.enumerated() {
    drawStop(at: CGPoint(x: x, y: lineY + forkDrop), pictogram: branchStops[k], palette: palettes[1])
}
// The transfers, on the borders: half in each picture. The last one is half of a transfer, before the phone of the app.
context.saveGState()
context.clip(to: CGRect(x: 0, y: 0, width: pic.width * CGFloat(linePictures), height: H))
for k in 1...linePictures {
    let c = CGPoint(x: pic.width * CGFloat(k), y: lineY), r = transferRadius, inner = r - transferRing
    context.setFillColor(cg(base))
    context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    context.setFillColor(cg(white))
    context.fillEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner))
}
context.restoreGState()

func drawBadge(_ p: Picture, centre: CGPoint) {
    guard let text = p.badge else { return }
    let s = badgeSize, rim: CGFloat = 9
    let outer = CGRect(x: centre.x - s / 2 - rim, y: centre.y - s / 2 - rim, width: s + 2 * rim, height: s + 2 * rim)
    let inner = CGRect(x: centre.x - s / 2, y: centre.y - s / 2, width: s, height: s)
    let shape = { (r: CGRect, k: CGFloat) -> CGPath in
        p.square ? CGPath(roundedRect: r, cornerWidth: 26 + k, cornerHeight: 26 + k, transform: nil) : CGPath(ellipseIn: r, transform: nil)
    }
    context.addPath(shape(outer, rim)); context.setFillColor(cg(white)); context.fillPath()
    context.addPath(shape(inner, 0)); context.setFillColor(cg(rgb(p.line))); context.fillPath()
    let font = NSFont.systemFont(ofSize: text.count > 1 ? 66 : 78, weight: .bold)
    let attributed = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg(rgb(p.badgeInk))])
    let line = CTLineCreateWithAttributedString(attributed)
    context.saveGState()
    context.translateBy(x: centre.x, y: centre.y)
    context.scaleBy(x: 1, y: -1)
    if p.square {
        // An RER letter: centred on its own glyph bounds, which already looks centred, as on the signs.
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
    } else if let glyphs = outlines(of: line, font: font), let ink = LabelInk(of: glyphs) {
        // A metro number: by the rule of the badge of the app (LabelInk), the weight of its ink across and its box
        // down, a little smaller when its weight would bring its ink nearer the edge than the margin. It is filled
        // from the outlines that were measured, so that its ink is where the measure says.
        let scale = min(1, s * (0.5 - badgeEdgeMargin) / ink.reach)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -ink.anchor.x, y: -ink.anchor.y)
        context.addPath(glyphs); context.setFillColor(cg(rgb(p.badgeInk))); context.fillPath()
    }
    context.restoreGState()
}
/// The outlines of a line of text, as CoreText lays out its glyphs (y up, the baseline at 0).
func outlines(of line: CTLine, font: CTFont) -> CGPath? {
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for k in 0..<count {
            guard let outline = CTFontCreatePathForGlyph(font, glyphs[k], nil) else { continue }
            path.addPath(outline, transform: CGAffineTransform(translationX: positions[k].x, y: positions[k].y))
        }
    }
    return path.isEmpty ? nil : path
}
for i in 0..<3 { drawBadge(pictures[i], centre: CGPoint(x: badgeX[i], y: lineY)) }

// MARK: The cuts of the screen

struct Corners: OptionSet { let rawValue: Int; static let top = Corners(rawValue: 1); static let bottom = Corners(rawValue: 2) }
func outline(_ rect: CGRect, _ corners: Corners) -> CGPath {
    let p = CGMutablePath()
    let tr: CGFloat = corners.contains(.top) ? corner : 0, br: CGFloat = corners.contains(.bottom) ? corner : 0
    p.move(to: CGPoint(x: rect.minX, y: rect.minY + tr))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tr, y: rect.minY), radius: tr)
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - br), radius: br)
    p.closeSubpath()
    return p
}
func draw(_ image: CGImage, in target: CGRect, clip: CGPath? = nil) {
    context.saveGState()
    if let clip { context.addPath(clip); context.clip() }
    context.translateBy(x: target.minX, y: target.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: target.size))
    context.restoreGState()
}
/// Draws a phone whose whole screen is at `screen` (in the picture), cut by the edge of the picture.
/// With the bezel: the capture fills its screen and the bezel goes over it, unchanged.
/// With none: only the rows `visible` of the screen, with rounded corners where the screen ends, and a shadow.
func phone(_ image: CGImage, screen: CGRect, visible: ClosedRange<CGFloat>, corners: Corners) {
    if let bezel {
        draw(image, in: screen, clip: bezel.screenShape(screen))
        draw(bezel.image, in: bezel.frame(around: screen))
        return
    }
    let rect = CGRect(x: screen.minX, y: visible.lowerBound, width: screen.width, height: visible.upperBound - visible.lowerBound)
    let path = outline(rect, corners)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 24), blur: 90, color: CGColor(gray: 0, alpha: 0.55))
    context.addPath(path); context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fillPath()
    context.restoreGState()
    draw(image, in: screen, clip: path)
}

let screenWidth = captureSize.width * captureScale, screenHeight = captureSize.height * captureScale
/// The x of the screen in its picture: the body of the bezel in the middle, or the screen when there is none.
let screenX = bezel.map { (pic.width - $0.body.width * $0.scale) / 2 + ($0.screen.minX - $0.body.minX) * $0.scale }
    ?? (pic.width - screenWidth) / 2
var recipe: [String] = []
for i in 0..<3 {
    let ox = pic.width * CGFloat(i) + screenX
    context.saveGState()
    context.clip(to: CGRect(x: pic.width * CGFloat(i), y: 0, width: pic.width, height: H))
    // The lock screen: the bottom of the screen (or of the phone) at `lockBottom`, its top off the edge.
    let lockScreenBottom = lockBottom - (bezel?.bottom ?? 0)
    phone(capture("lock-\(pictures[i].name)"),
          screen: CGRect(x: ox, y: lockScreenBottom - screenHeight, width: screenWidth, height: screenHeight),
          visible: 0...lockScreenBottom, corners: .bottom)
    // The island: the status bar of a second phone. With the bezel, its top is cut by the bottom edge of the
    // picture under the strip, so no Home Screen shows; with none, the strip floats.
    let islandScreenTop = bezel == nil ? islandTop : H - islandRows * captureScale
    let island = capture("island-\(pictures[i].name)")
    let strip = island.cropping(to: CGRect(x: 0, y: 0, width: island.width, height: Int(islandRows)))!
    if let bezel {
        let screen = CGRect(x: ox, y: islandScreenTop, width: screenWidth, height: screenHeight)
        draw(strip, in: CGRect(x: ox, y: islandScreenTop, width: screenWidth, height: islandRows * captureScale),
             clip: bezel.screenShape(screen))
        draw(bezel.image, in: bezel.frame(around: screen))
    } else {
        phone(strip, screen: CGRect(x: ox, y: islandScreenTop, width: screenWidth, height: islandRows),
              visible: islandScreenTop...(islandScreenTop + islandRows), corners: [.top, .bottom])
    }
    context.restoreGState()
    drawText(headlines[i], palette: palettes[i], originX: pic.width * CGFloat(i), top: textTop)
}
do {   // The app: the whole top of the phone, its screen cut by the bottom edge just under the link Help and feedback.
    let ox = 3 * pic.width + screenX
    context.saveGState()
    context.clip(to: CGRect(x: 3 * pic.width, y: 0, width: pic.width, height: H))
    phone(capture("app"), screen: CGRect(x: ox, y: appScreenTop, width: screenWidth, height: screenHeight),
          visible: appScreenTop...H, corners: .top)
    context.restoreGState()
    let textTop = appTextCentre - maxFontSize * lineStep
    drawText(headlines[3], palette: palettes[3], originX: 3 * pic.width, top: textTop)
    recipe.append("app rows 0-\(Int(appLastRow)) off the bottom edge, the phone starts at y \(Int(appPhoneTop)), headline centre \(Int(appTextCentre))")
}

// MARK: Cut the panorama into the pictures

let panorama = context.makeImage()!
for (i, p) in pictures.enumerated() {
    write(panorama.cropping(to: CGRect(x: pic.width * CGFloat(i), y: 0, width: pic.width, height: pic.height))!,
          "\(outDir)/\(language)-\(i + 1)-\(p.name).png")
}
switch bezelResult {
case .fits(let b):
    print(String(format: "Frame: the bezel %@ (%d x %d, screen %d x %d, corners %d), at scale %.3f; captures at scale %.3f",
                 bezelPath, b.image.width, b.image.height, Int(b.screen.width), Int(b.screen.height), Int(b.screenCorner),
                 b.scale, b.captureScale))
case .none(let reason):
    print("Frame: none, because \(reason); the cuts have rounded corners, at scale 1.0")
}
print(String(format: "Headlines: SF bold %.0f; stops: %@", fontSize, showsPictograms ? "pictograms" : "dots"))
for line in recipe { print(line) }
