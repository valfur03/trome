import Foundation

/// Reads the Swift files of the tests, and finds each suite that holds tests and lacks the trait `.bounded`.
///
/// A suite is a type declared at the top of a file. Its tests are in its body, or in an extension of it, in any file;
/// a type nested in a suite takes the trait of the suite. The comments and the texts in quotes are left out, so a
/// brace or an `@Test` written in them counts for nothing.
enum BoundedSuites {
    struct Missing: Equatable, CustomStringConvertible {
        let file: String
        let line: Int
        let name: String

        var description: String { "\(file):\(line): \(name)" }
    }

    /// A declaration at the top of a file, with the code of its attributes and of its body.
    private struct Declaration {
        let kind: String
        let name: String
        let line: Int
        let attributes: ArraySlice<UInt8>
        let body: ArraySlice<UInt8>
    }

    /// The suites of `files` (path and text) that hold tests and lack the trait, and the top-level test functions
    /// that lack it, in the order of the files.
    static func missing(in files: [(path: String, text: String)]) -> [Missing] {
        var declared: Set<String> = []
        var unbounded: [String: Missing] = [:]
        var holdingTests: [String] = []
        var missing: [Missing] = []
        for file in files {
            for declaration in declarations(in: code(file.text)) {
                let place = Missing(file: file.path, line: declaration.line, name: declaration.name)
                switch declaration.kind {
                case "func":
                    if contains(declaration.attributes, "@Test") && !hasTrait(declaration.attributes) {
                        missing.append(place)
                    }
                case "extension":
                    if contains(declaration.body, "@Test") {
                        holdingTests.append(String(declaration.name.prefix { $0 != "." }))
                    }
                default:
                    declared.insert(declaration.name)
                    unbounded[declaration.name] = hasTrait(declaration.attributes) ? nil : place
                    if contains(declaration.body, "@Test") { holdingTests.append(declaration.name) }
                }
            }
        }
        var seen: Set<String> = []
        for name in holdingTests where seen.insert(name).inserted {
            if !declared.contains(name) { missing.append(Missing(file: "no file declares it", line: 0, name: name)) }
            missing += [unbounded[name]].compactMap { $0 }
        }
        return missing
    }

    /// The bytes of `text` with its comments and the contents of its texts in quotes made spaces, line breaks kept.
    static func code(_ text: String) -> [UInt8] {
        var scanner = CodeScanner(source: Array(text.utf8))
        scanner.run()
        return scanner.code
    }

    /// True when an `@Suite(...)` or `@Test(...)` of `attributes` lists `.bounded`.
    private static func hasTrait(_ attributes: ArraySlice<UInt8>) -> Bool {
        let trait = Array(".bounded".utf8)
        for attribute in ["@Suite(", "@Test("] {
            for start in positions(of: attribute, in: attributes) {
                var end = start + attribute.utf8.count
                var depth = 1
                while depth > 0, end < attributes.endIndex {
                    if attributes[end] == UInt8(ascii: "(") { depth += 1 }
                    if attributes[end] == UInt8(ascii: ")") { depth -= 1 }
                    end += 1
                }
                let found = positions(of: ".bounded", in: attributes[start..<end])
                if found.contains(where: { !isWordByte(attributes[$0 + trait.count]) }) { return true }
            }
        }
        return false
    }

    /// The declarations at the top of `code`: types, extensions and functions, each with its body.
    private static func declarations(in code: [UInt8]) -> [Declaration] {
        var found: [Declaration] = []
        var depth = 0
        var headerStart = 0
        var bodyStart = 0
        for (index, byte) in code.enumerated() {
            if byte == UInt8(ascii: "{") {
                if depth == 0 { bodyStart = index }
                depth += 1
            } else if byte == UInt8(ascii: "}"), depth > 0 {
                depth -= 1
                guard depth == 0 else { continue }
                if let declaration = declaration(code, header: headerStart..<bodyStart, body: bodyStart..<index) {
                    found.append(declaration)
                }
                headerStart = index + 1
            }
        }
        return found
    }

    private static let kinds = ["struct", "class", "enum", "actor", "extension", "func", "protocol"]

    /// The last declaration keyword of the header names the block; the code before it holds its attributes.
    private static func declaration(_ code: [UInt8], header: Range<Int>, body: Range<Int>) -> Declaration? {
        for index in header.reversed() where isWordByte(code[index]) && (index == 0 || !isWordByte(code[index - 1])) {
            let keyword = word(in: code, at: index)
            guard kinds.contains(keyword) else { continue }
            var nameStart = index + keyword.utf8.count
            while nameStart < header.upperBound, code[nameStart] == UInt8(ascii: " ") { nameStart += 1 }
            let name = word(in: code, at: nameStart, dots: true)
            guard !name.isEmpty else { return nil }
            return Declaration(
                kind: keyword,
                name: name,
                line: code[..<index].count(where: { $0 == UInt8(ascii: "\n") }) + 1,
                attributes: code[header.lowerBound..<index],
                body: code[body]
            )
        }
        return nil
    }

    private static func contains(_ code: ArraySlice<UInt8>, _ text: String) -> Bool {
        code.firstRange(of: Array(text.utf8)) != nil
    }

    /// The start of each place of `text` in `code`.
    private static func positions(of text: String, in code: ArraySlice<UInt8>) -> [Int] {
        code.ranges(of: Array(text.utf8)).map(\.lowerBound)
    }

    static func isWordByte(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_") || (byte >= 0x30 && byte <= 0x39) || (byte | 0x20 >= 0x61 && byte | 0x20 <= 0x7A)
    }

    private static func word(in code: [UInt8], at start: Int, dots: Bool = false) -> String {
        var end = start
        while end < code.count, isWordByte(code[end]) || (dots && code[end] == UInt8(ascii: ".")) { end += 1 }
        return String(bytes: code[start..<end], encoding: .utf8) ?? ""
    }
}

/// Makes spaces of the comments of Swift code and of the contents of its texts in quotes, line breaks kept.
private struct CodeScanner {
    private enum Mode {
        /// Code; inside the `\( )` of a text, with the depth of its other parentheses.
        case code(interpolation: Int?)
        case text(hashes: Int, multiline: Bool)
    }

    private let source: [UInt8]
    private(set) var code: [UInt8]
    private var modes: [Mode] = [.code(interpolation: nil)]
    private var index = 0

    init(source: [UInt8]) {
        self.source = source
        code = source
    }

    mutating func run() {
        while index < source.count {
            switch modes[modes.count - 1] {
            case .code(let interpolation):
                scanCode(interpolation: interpolation)
            case .text(let hashes, let multiline):
                scanText(hashes: hashes, multiline: multiline)
            }
        }
    }

    private static let slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*")
    private static let quote = UInt8(ascii: "\"")

    private mutating func scanCode(interpolation: Int?) {
        let byte = source[index]
        let quote = index + hashes(at: index)
        if byte == Self.slash, self.byte(at: index + 1) == Self.slash {
            skip(to: source[index...].firstIndex(of: UInt8(ascii: "\n")) ?? source.count)
        } else if byte == Self.slash, self.byte(at: index + 1) == Self.star {
            skipBlockComment()
        } else if self.byte(at: quote) == Self.quote {
            let multiline = self.byte(at: quote + 1) == Self.quote && self.byte(at: quote + 2) == Self.quote
            modes.append(.text(hashes: quote - index, multiline: multiline))
            skip(to: quote + (multiline ? 3 : 1))
        } else if let depth = interpolation, byte == UInt8(ascii: ")"), depth == 0 {
            modes.removeLast()
            skip(to: index + 1)
        } else {
            if let depth = interpolation, byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")") {
                modes[modes.count - 1] = .code(interpolation: depth + (byte == UInt8(ascii: "(") ? 1 : -1))
            }
            index = max(quote, index + 1)
        }
    }

    private mutating func scanText(hashes count: Int, multiline: Bool) {
        let width = multiline ? 3 : 1
        if source[index] == UInt8(ascii: "\\"), hashes(at: index + 1) >= count {
            let next = index + 1 + count
            if byte(at: next) == UInt8(ascii: "(") { modes.append(.code(interpolation: 0)) }
            skip(to: next + 1)
        } else if (0..<width).allSatisfy({ byte(at: index + $0) == Self.quote }), hashes(at: index + width) >= count {
            modes.removeLast()
            skip(to: index + width + count)
        } else {
            skip(to: index + 1)
        }
    }

    private mutating func skipBlockComment() {
        let begin = index
        var nesting = 0
        repeat {
            if byte(at: index) == Self.slash, byte(at: index + 1) == Self.star {
                nesting += 1
                index += 2
            } else if byte(at: index) == Self.star, byte(at: index + 1) == Self.slash {
                nesting -= 1
                index += 2
            } else {
                index += 1
            }
        } while nesting > 0 && index < source.count
        let end = index
        index = begin
        skip(to: end)
    }

    /// Makes spaces of the bytes up to `end`, line breaks kept, and goes on from there.
    private mutating func skip(to end: Int) {
        let end = min(end, source.count)
        while index < end {
            if source[index] != UInt8(ascii: "\n") { code[index] = UInt8(ascii: " ") }
            index += 1
        }
    }

    /// The byte at `position`, or 0 past the end.
    private func byte(at position: Int) -> UInt8 {
        position < source.count ? source[position] : 0
    }

    private func hashes(at position: Int) -> Int {
        var end = position
        while end < source.count, source[end] == UInt8(ascii: "#") { end += 1 }
        return end - position
    }
}
