import AppIntents
import RATPCore
import SwiftUI

struct LinesPagerButton<Content: View>: View {
    static var tapRoomAbove: CGFloat { 10 }
    static var minimumTapHeight: CGFloat { 44 }

    let page: LinesPage
    let pageName: Text
    @ViewBuilder let content: Content

    var body: some View {
        if page.hasOtherLines {
            TapRoomLayout(roomAbove: Self.tapRoomAbove, minimumHeight: Self.minimumTapHeight) {
                Button(intent: ShowNextLinesIntent()) {
                    content
                        .padding(.top, Self.tapRoomAbove)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text("\(pageName), \(Text("Show the next line")), \(Text("\(page.otherLineCount) other lines"))")
                )
                .accessibilityAddTraits(.isButton)
            }
            .zIndex(1)
        } else {
            content
        }
    }
}

private struct TapRoomLayout: Layout {
    let roomAbove: CGFloat
    let minimumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let button = subviews.first else { return .zero }
        let size = button.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: max(0, size.height - roomAbove))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY - roomAbove),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: max(minimumHeight, bounds.height + roomAbove))
        )
    }
}
