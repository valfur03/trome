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
        CircleLayout {
            name
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(3)
        }
        .font(size == .regular ? .subheadline.bold() : .caption.bold())
        .foregroundStyle(isShown ? line.badgeTextColor : .secondary)
        .background(isShown ? line.badgeColor : .clear, in: Circle())
        .overlay(Circle().stroke(isShown ? .clear : line.badgeColor, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.localizedName)
    }

    private var name: Text {
        guard line.name.hasSuffix(Self.bis) else { return Text(line.name) }
        return Text(line.name.dropLast(Self.bis.count))
            + Text(Self.bis).font(.caption2.bold())
    }

    private static let bis = "bis"
}

private struct CircleLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.first?.sizeThatFits(.unspecified).height ?? 0
        return CGSize(width: height, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(bounds.size)
        )
    }
}
