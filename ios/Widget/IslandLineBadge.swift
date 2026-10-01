import RATPCore
import SwiftUI

struct IslandLineBadge: View {
    static let rerSide: CGFloat = 26
    static let rerCornerRadius: CGFloat = 5

    let line: TransitLine

    var body: some View {
        switch line.mode {
        case .metro:
            MetroLineBadge(line: line, size: .regular)
        case .rer:
            Text(verbatim: line.name)
                .font(.subheadline.bold())
                .lineLimit(1)
                .fixedSize()
                .padding(3)
                .frame(minWidth: Self.rerSide, minHeight: Self.rerSide)
                .foregroundStyle(line.badgeTextColor)
                .background(line.badgeColor, in: RoundedRectangle(cornerRadius: Self.rerCornerRadius))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.localizedName)
        }
    }
}
