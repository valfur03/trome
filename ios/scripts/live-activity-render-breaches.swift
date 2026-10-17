import AppKit
import Foundation
import Vision

struct DrawnText: Decodable {
    let left: CGFloat
    let top: CGFloat
    let width: CGFloat
    let height: CGFloat
    let isTruncated: Bool
    let visibleCharacters: Int
    let ocr: String?
}

struct ExpectedText: Decodable, Hashable {
    let kind: String
    let text: String
    let line: Int?
    let direction: Int?

    func shown(_ count: Int) -> String {
        String(text.prefix(count)) + "…"
    }
}

struct ImageTexts: Decodable {
    let image: String
    let station: String
    let page: Int
    let isStale: Bool
    let surface: String
    let size: String
    let height: CGFloat
    let drawn: [DrawnText]
    let expected: [ExpectedText]
}

enum BreachKind: String, CaseIterable {
    case time = "time-cut"
    case destination = "destination-under-6"
    case sameDirections = "same-two-directions"
    case label = "label-cut"

    var title: String {
        switch self {
        case .time: "time cut"
        case .destination: "destination under 6"
        case .sameDirections: "two directions the same"
        case .label: "label cut"
        }
    }
}

struct Breach {
    let kind: BreachKind
    let render: ImageTexts
    let shown: String
}

struct CutText {
    enum Name {
        case time(String)
        case expected([ExpectedText])
        case destinationCutToNothing
        case unnamed(String)
    }

    let text: DrawnText
    let name: Name
}

enum Naming {
    static let floor = 6
    static let noise = CharacterSet(charactersIn: "….·•*¿>→-_,:;|")
        .union(.whitespacesAndNewlines)

    static func cleaned(_ ocr: String) -> String {
        var text = Substring(ocr)
        while let last = text.unicodeScalars.last, noise.contains(last) { text = text.dropLast() }
        while let first = text.unicodeScalars.first, noise.contains(first) { text = text.dropFirst() }
        return String(text)
    }

    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    static func isTime(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.first?.isNumber == true || lowered == "dans" || lowered.hasPrefix("dans ")
            || lowered.hasPrefix("in ")
    }

    static func score(of seen: String, against expected: String) -> Double {
        guard !expected.isEmpty, !seen.isEmpty else { return 0 }
        if seen == expected || (seen.hasSuffix(expected) && seen.count - expected.count <= 3) { return 1 }
        guard expected.count >= 4 else { return 0 }
        let tail = String(seen.suffix(expected.count))
        let distance = min(levenshtein(seen, expected), levenshtein(tail, expected))
        return 1 - Double(distance) / Double(expected.count)
    }

    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (index, character) in left.enumerated() {
            var current = [index + 1]
            for (otherIndex, other) in right.enumerated() {
                current.append(
                    min(previous[otherIndex + 1] + 1, current[otherIndex] + 1,
                        previous[otherIndex] + (character == other ? 0 : 1))
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    static func name(_ text: DrawnText, seen ocr: String, in render: ImageTexts) -> CutText.Name {
        let seen = cleaned(ocr)
        if isTime(seen) { return .time(seen) }
        let normalizedSeen = normalized(seen)
        let scored = render.expected.map { expected in
            (expected, score(of: normalizedSeen, against: normalized(String(expected.text.prefix(text.visibleCharacters)))))
        }
        if let best = scored.map(\.1).max(), best >= 0.75 {
            return .expected(scored.filter { $0.1 == best }.map(\.0))
        }
        if normalizedSeen.isEmpty || text.visibleCharacters == 0 {
            let rightEdge = render.drawn.map { $0.left + $0.width }.max() ?? 0
            return text.left + text.width >= rightEdge - 1 ? .time(seen) : .destinationCutToNothing
        }
        return .unnamed(seen)
    }
}

enum Recognition {
    static let margin: CGFloat = 3
    static let padding = 24

    static func texts(in render: ImageTexts, folder: URL) throws -> [String]? {
        let cuts = render.drawn.filter(\.isTruncated)
        if cuts.allSatisfy({ $0.ocr != nil }) { return cuts.map { $0.ocr ?? "" } }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(render.image)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scale = CGFloat(cgImage.height) / render.height
        return try cuts.map { text in
            let frame = CGRect(x: text.left, y: text.top, width: text.width, height: text.height)
                .insetBy(dx: -margin, dy: -margin)
            let pixels = CGRect(
                x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale
            ).integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            guard let crop = cgImage.cropping(to: pixels), let padded = padded(crop) else { return "" }
            return try recognized(padded)
        }
    }

    static func padded(_ image: CGImage) -> CGImage? {
        let width = image.width + 2 * padding
        let height = image.height + 2 * padding
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(.black)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
        return context.makeImage()
    }

    // It throws when the text recognition fails: an empty text would be named a destination cut to nothing, a false breach.
    static func recognized(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}

enum Breaches {
    static func of(_ render: ImageTexts, seen: [String]) -> (breaches: [Breach], unnamed: [String]) {
        let named = zip(render.drawn.filter(\.isTruncated), seen).map { text, ocr in
            CutText(text: text, name: Naming.name(text, seen: ocr, in: render))
        }
        let destinationColumn = named.compactMap { cut -> CGFloat? in
            guard case .expected(let texts) = cut.name, texts.allSatisfy({ $0.kind == "destination" }) else { return nil }
            return cut.text.left
        }.min()
        let cuts = named.map { cut in
            guard case .expected(let texts) = cut.name else { return cut }
            return CutText(text: cut.text, name: .expected(oneKind(of: texts, at: cut.text, destinationColumn: destinationColumn)))
        }
        var breaches: [Breach] = []
        var unnamed: [String] = []
        var destinations: [(CutText, [ExpectedText])] = []
        for cut in cuts {
            let count = cut.text.visibleCharacters
            switch cut.name {
            case .time(let seen):
                breaches.append(Breach(kind: .time, render: render, shown: seen + "…"))
            case .destinationCutToNothing:
                breaches.append(Breach(kind: .destination, render: render, shown: "…"))
            case .unnamed(let seen):
                unnamed.append(seen)
            case .expected(let texts):
                let first = texts[0]
                if first.kind == "label" {
                    breaches.append(Breach(kind: .label, render: render, shown: first.shown(count)))
                } else if first.kind == "destination" {
                    destinations.append((cut, texts))
                    if count < Naming.floor {
                        breaches.append(Breach(kind: .destination, render: render, shown: first.shown(count)))
                    }
                }
            }
        }
        for (index, (cut, texts)) in destinations.enumerated() {
            for (other, otherTexts) in destinations[(index + 1)...] {
                if let pair = sameDirections(texts, cut.text.visibleCharacters, otherTexts, other.text.visibleCharacters) {
                    breaches.append(Breach(kind: .sameDirections, render: render, shown: pair))
                }
            }
        }
        return (breaches, unnamed)
    }

    static func oneKind(of texts: [ExpectedText], at text: DrawnText, destinationColumn: CGFloat?) -> [ExpectedText] {
        let isLeftOfTheDestinations = destinationColumn.map { text.left < $0 - 1 } ?? false
        let kinds = isLeftOfTheDestinations ? ["label", "destination", "station"] : ["destination", "label", "station"]
        for kind in kinds where texts.contains(where: { $0.kind == kind }) {
            return texts.filter { $0.kind == kind }
        }
        return texts
    }

    static func sameDirections(
        _ texts: [ExpectedText], _ count: Int, _ otherTexts: [ExpectedText], _ otherCount: Int
    ) -> String? {
        for text in texts {
            for other in otherTexts where text.line != nil && text.line == other.line
                && text.direction != other.direction && text.text != other.text
                && Naming.normalized(String(text.text.prefix(count)))
                    == Naming.normalized(String(other.text.prefix(otherCount))) {
                return "\(text.shown(count)) / \(other.shown(otherCount))"
            }
        }
        return nil
    }
}

func csvField(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

let surfaces = [("lock17", "iPhone 17, lock screen"), ("lockSE", "iPhone SE, lock screen"), ("island17", "iPhone 17, island")]
let sizes = ["L", "XXXL"]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: live-activity-render-breaches.swift <language folder>\n".utf8))
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let renders: [ImageTexts]
do {
    renders = try JSONDecoder().decode(
        [ImageTexts].self, from: Data(contentsOf: folder.appendingPathComponent("texts.json"))
    )
} catch {
    FileHandle.standardError.write(Data("Cannot read \(folder.path)/texts.json: \(error)\n".utf8))
    exit(1)
}

var recognized = [[String]?](repeating: nil, count: renders.count)
var failure: (image: String, error: Error)?
let lock = NSLock()
DispatchQueue.concurrentPerform(iterations: renders.count) { index in
    do {
        let texts = try Recognition.texts(in: renders[index], folder: folder)
        lock.withLock { recognized[index] = texts }
    } catch {
        lock.withLock { failure = failure ?? (renders[index].image, error) }
    }
}
if let failure {
    FileHandle.standardError.write(Data("The text recognition of this Mac failed on \(failure.image): \(failure.error)\n".utf8))
    exit(1)
}
let unreadable = zip(renders, recognized).filter { $0.1 == nil }.map(\.0.image)
guard unreadable.isEmpty else {
    let images = unreadable.joined(separator: ", ")
    FileHandle.standardError.write(Data("Cannot read the images of \(folder.path)/texts.json: \(images)\n".utf8))
    exit(1)
}
let seen = recognized.map { $0 ?? [] }

var breaches: [Breach] = []
var unnamed: [(ImageTexts, String)] = []
for (render, texts) in zip(renders, seen) {
    let found = Breaches.of(render, seen: texts)
    breaches += found.breaches
    unnamed += found.unnamed.map { (render, $0) }
}
breaches = breaches.enumerated()
    .sorted { ($0.element.kind.rawValue, $0.element.render.image, $0.offset) < ($1.element.kind.rawValue, $1.element.render.image, $1.offset) }
    .map(\.element)

let csv = ["kind,station,page,stale,surface,size,image,shown"] + breaches.map { breach in
    let render = breach.render
    return [
        breach.kind.rawValue, csvField(render.station), "\(render.page)", "\(render.isStale)", render.surface,
        render.size, csvField(render.image), csvField(breach.shown)
    ].joined(separator: ",")
}
let list = folder.appendingPathComponent("breaches.csv")
try csv.joined(separator: "\n").appending("\n").write(to: list, atomically: true, encoding: .utf8)

let stations = Set(renders.map(\.station)).count
print("Breaches of the cut rules (texts cut too much), in the images of \(stations) stations: \(breaches.count) (list: \(list.path))")
for (surface, title) in surfaces {
    for size in sizes {
        let counts = BreachKind.allCases.map { kind in
            let count = breaches.filter { $0.kind == kind && $0.render.surface == surface && $0.render.size == size }
                .count
            return "\(kind.title) \(count)"
        }
        print("  \(title), \(size): \(counts.joined(separator: ", "))")
    }
}
for breach in breaches {
    let render = breach.render
    let stale = render.isStale ? " stale" : ""
    print("  \(breach.kind.title): \(breach.shown) | \(render.station) p\(render.page)\(stale) \(render.surface) \(render.size) | \(render.image)")
}
print("Other cut texts (not a time, a destination, a label or a station name; a person reads them): \(unnamed.count)")
for (render, text) in unnamed.prefix(10) {
    print("  \(text)… | \(render.image)")
}
