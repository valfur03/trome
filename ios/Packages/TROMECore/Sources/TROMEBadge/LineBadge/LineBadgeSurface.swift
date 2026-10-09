import SwiftUI

/// Where a line badge is drawn, and how big it is there at the default text size.
public enum LineBadgeSurface: String, CaseIterable, Sendable {
    /// The header of the lock screen (also the button of the hub pager) and the line badges of the app screen.
    case header
    /// The rows of a page with several lines, on the lock screen and in the expanded Dynamic Island.
    case lineRow
    /// The compact Dynamic Island, which keeps its size at every text size.
    case compactIsland

    public var diameter: CGFloat {
        switch self {
        case .header: 24
        case .lineRow: 20
        case .compactIsland: 24
        }
    }

    /// The text style whose growth the badge follows. A row follows the footnote: its badge then grows as the text
    /// badge of the rows did (27.5 pt at the largest size of a Live Activity, 26.6 pt now), so that the destinations
    /// next to it keep their room; the caption would grow it to 28.8 pt and cut one more letter of some of them.
    var textStyle: Font.TextStyle {
        switch self {
        case .header, .compactIsland: .subheadline
        case .lineRow: .footnote
        }
    }

    var scalesWithText: Bool {
        self != .compactIsland
    }
}
