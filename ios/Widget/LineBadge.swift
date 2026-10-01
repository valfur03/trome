import RATPCore
import SwiftUI

struct LineBadge: View {
    let line: TransitLine

    var body: some View {
        Text(line.localizedName)
            .font(.subheadline.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(line.badgeTextColor)
            .background(line.badgeColor, in: Capsule())
    }
}

struct SmallLineBadge: View {
    static let minimumWidth: CGFloat = 24

    let line: TransitLine

    var body: some View {
        switch line.mode {
        case .metro:
            MetroLineBadge(line: line)
        case .rer:
            RERLineBadge(line: line)
        }
    }
}

private struct RERLineBadge: View {
    let line: TransitLine

    var body: some View {
        Text(line.name)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: SmallLineBadge.minimumWidth)
            .foregroundStyle(line.badgeTextColor)
            .background(line.badgeColor, in: Capsule())
            .accessibilityLabel(line.localizedName)
    }
}
