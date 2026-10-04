import SwiftUI

/// The look of the app screen: a night page after the Live Activity, the same in the light and the dark mode of the
/// phone. Change a colour or a size here, and the whole screen follows.
///
/// Colours (each text on its background keeps a contrast of at least 4.5:1):
/// - The page: a gradient from `pageTop` at the top to `pageBottom` from the middle down.
/// - A card: `card`, with `text`, and `secondaryText` for the explanations and the overlines.
/// - A divider inside a card, and the background of a chip: `divider`.
/// - The plate (the Live Activity in small): a gradient from `plateTop` to `plateBottom`, with a 1 pt border of white
///   at 12%, and white text.
/// - A state that is fine: a `fine` pill. A state that the rider must fix: a `problem` pill, a `problem` border of
///   2 pt on its card, and a `problem` button inside that card. Nothing else on the page is orange.
/// - A link in a text: `link`.
///
/// Type: the system font, which grows with the text size of the phone. The screen title is a bold large title, the
/// title of the plate a bold title 2, a row title a headline. An overline is a bold caption in capitals, with wide
/// tracking, in `secondaryText`. An explanation is a footnote in `secondaryText`. A pill is a heavy caption in
/// capitals, with an icon.
///
/// Shapes and spacing: a card has continuous corners of `cardCorner`, the plate of `plateCorner`. The page margin is
/// `pageMargin`, the space between two cards `cardSpacing`, the padding inside a card `cardPadding`
/// (`platePadding` in the plate).
///
/// Elements:
/// - A row: an `IconChip` (32 pt, 9 pt corners), its title, and an arrow up and right when it opens a web page.
/// - A state: a `StatePill`, a filled capsule with an icon and a word: a check when fine, a triangle when the rider
///   must act, and the icon of the state when it is a choice of the rider (a snooze).
/// - A button: a capsule at least 48 pt high (`ProblemButtonStyle`), or a grey `ChipLabel` at least 44 pt high for a
///   quiet action. The switch and the menus stay the system ones.
enum NightLook {
    static let pageTop = Color(hex: 0x0F1752)
    static let pageBottom = Color(hex: 0x05060D)
    static let card = Color(hex: 0x161A2E)
    static let text = Color(hex: 0xF4F5F8)
    static let secondaryText = Color(hex: 0xA3A9BE)
    static let divider = Color(hex: 0x262B45)
    static let plateTop = Color(hex: 0x2A3BC0)
    static let plateBottom = Color(hex: 0x141E78)
    static let fine = Color(hex: 0x157A3F)
    static let problem = Color(hex: 0xB04A00)
    static let link = Color(hex: 0x9AA6FF)
    static let showingDot = Color(hex: 0x30D158)

    static let pageMargin: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let platePadding: CGFloat = 18
    static let cardCorner: CGFloat = 20
    static let plateCorner: CGFloat = 24
    static let problemBorder: CGFloat = 2
    static let minimumTapHeight: CGFloat = 44
    static let buttonHeight: CGFloat = 48

    static let page = LinearGradient(colors: [pageTop, pageBottom], startPoint: .top, endPoint: .center)
    static let plate = LinearGradient(
        colors: [plateTop, plateBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
