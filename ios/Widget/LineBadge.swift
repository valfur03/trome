import RATPCore
import SwiftUI

struct LineBadge: View {
    let line: TransitLine

    var body: some View {
        Text(line.localizedName)
            .font(.subheadline.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

struct SmallLineBadge: View {
    static let minimumWidth: CGFloat = 24

    let line: TransitLine
    let isShown: Bool

    var body: some View {
        switch line.mode {
        case .metro:
            MetroLineBadge(line: line, isShown: isShown)
        case .rer:
            RERLineBadge(line: line, isShown: isShown)
        }
    }
}

private struct RERLineBadge: View {
    let line: TransitLine
    let isShown: Bool

    var body: some View {
        Text(line.name)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: SmallLineBadge.minimumWidth)
            .background(isShown ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(isShown ? .primary : .secondary)
            .accessibilityLabel(line.localizedName)
    }
}

struct OtherLinesBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "+\(count)")
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: SmallLineBadge.minimumWidth)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
