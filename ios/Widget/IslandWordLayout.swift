import SwiftUI

struct IslandWordLayout: Layout {
    let maximumWidth: CGFloat
    let wrappedCornerInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let word = subviews.first else { return .zero }
        let (size, isWrapped) = layout(of: word)
        return CGSize(width: size.width + (isWrapped ? wrappedCornerInset : 0), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let word = subviews.first else { return }
        let (size, isWrapped) = layout(of: word)
        word.place(
            at: CGPoint(x: bounds.maxX - (isWrapped ? wrappedCornerInset : 0), y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(size)
        )
    }

    private func layout(of word: LayoutSubview) -> (size: CGSize, isWrapped: Bool) {
        let oneLine = word.sizeThatFits(.unspecified)
        guard oneLine.width > maximumWidth else { return (oneLine, false) }
        return (word.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil)), true)
    }
}
