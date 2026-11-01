#if DEBUG
import Foundation

/// The fields of one entry of a PRIM answer that only the debug log writes (`PRIMAnswerLog`), as PRIM gave them.
/// They tell two entries of one minute apart: a plan entry that was never updated, or a real second train.
/// Only a Debug build reads them, so a Release build parses and keeps none of them.
/// They never change what the app does with a train, so they never make two visits differ (`==` is always true).
struct PRIMLogFields: Equatable, Sendable {
    /// Each field with its name in the log, which is its name in the PRIM answer, in the order of the log line.
    var fields: [(name: String, value: PRIMRawValue?)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

/// One field of a PRIM answer as text, whatever its JSON shape: the texts, numbers and flags that it holds, joined
/// by commas (`[{"value": "UZAR"}]` gives `UZAR`, `{"TrainNumberRef": [{"value": "1"}, {"value": "2"}]}` gives `1,2`).
/// An empty list or object is `empty`, and an empty text is `""`, so that neither reads like a value.
struct PRIMRawValue: Decodable, Equatable, Sendable {
    let text: String

    init(text: String) {
        self.text = text
    }

    init(from decoder: any Decoder) throws {
        let leaves = Self.leaves(from: decoder)
        text = leaves.isEmpty ? "empty" : leaves.map { $0.isEmpty ? "\"\"" : $0 }.joined(separator: ",")
    }

    private static func leaves(from decoder: any Decoder) -> [String] {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() { return ["null"] }
            if let text = try? container.decode(String.self) { return [text] }
            if let flag = try? container.decode(Bool.self) { return [String(flag)] }
            if let number = try? container.decode(Int.self) { return [String(number)] }
            if let number = try? container.decode(Double.self) { return [String(number)] }
        }
        if let object = try? decoder.container(keyedBy: AnyKey.self) {
            return object.allKeys.sorted { $0.stringValue < $1.stringValue }.flatMap { key in
                (try? object.decode(Nested.self, forKey: key))?.leaves ?? []
            }
        }
        if var list = try? decoder.unkeyedContainer() {
            var leaves: [String] = []
            while !list.isAtEnd {
                guard let nested = try? list.decode(Nested.self) else { break }
                leaves += nested.leaves
            }
            return leaves
        }
        return []
    }

    private struct Nested: Decodable {
        let leaves: [String]

        init(from decoder: any Decoder) throws {
            leaves = PRIMRawValue.leaves(from: decoder)
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}
#endif
