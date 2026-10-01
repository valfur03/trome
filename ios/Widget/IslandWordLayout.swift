import SwiftUI

struct IslandWordLayout: Layout {
    let maximumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first.map(size(of:)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let word = subviews.first else { return }
        word.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(size(of: word))
        )
    }

    private func size(of word: LayoutSubview) -> CGSize {
        let oneLine = word.sizeThatFits(.unspecified)
        guard oneLine.width > maximumWidth else { return oneLine }
        return word.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil))
    }
}
