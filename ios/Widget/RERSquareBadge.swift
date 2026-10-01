import RATPCore
import SwiftUI

struct RERSquareBadge: View {
    let line: TransitLine

    var body: some View {
        SquareLayout {
            Text(line.name)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(3)
        }
        .font(.subheadline.bold())
        .foregroundStyle(line.badgeTextColor)
        .background(line.badgeColor, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.localizedName)
    }
}

private struct SquareLayout: Layout {
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
