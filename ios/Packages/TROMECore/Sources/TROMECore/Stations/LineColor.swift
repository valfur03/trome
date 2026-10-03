import Foundation

public struct LineColor: Codable, Hashable, Sendable {
    public struct RGB: Hashable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double
    }

    public var background: String
    public var text: String

    public init(background: String, text: String) {
        self.background = background
        self.text = text
    }

    public var backgroundRGB: RGB? {
        RGB(hex: background)
    }

    public var textRGB: RGB? {
        RGB(hex: text)
    }
}

extension LineColor.RGB {
    init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
