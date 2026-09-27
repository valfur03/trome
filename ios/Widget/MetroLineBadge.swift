import RATPCore
import SwiftUI

struct MetroLineBadge: View {
    enum Size {
        case regular
        case small
    }

    let line: TransitLine
    var size = Size.small
    var isShown = true

    var body: some View {
        ZStack {
            Text(verbatim: "00")
                .hidden()
            Text(line.name)
        }
        .font(size == .regular ? .subheadline.bold() : .caption.bold())
        .lineLimit(1)
        .fixedSize()
        .padding(3)
        .foregroundStyle(isShown ? line.badgeTextColor : .secondary)
        .background(isShown ? line.badgeColor : .clear, in: Capsule())
        .overlay(Capsule().stroke(isShown ? .clear : line.badgeColor, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.localizedName)
    }
}
