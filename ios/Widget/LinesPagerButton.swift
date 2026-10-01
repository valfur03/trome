import AppIntents
import RATPCore
import SwiftUI

struct LinesPagerButton<Content: View>: View {
    static var tapRoomAbove: CGFloat { 10 }
    static var tapRoomBelow: CGFloat { 8 }

    let page: LinesPage
    let pageName: Text
    @ViewBuilder let content: Content

    var body: some View {
        if page.hasOtherLines {
            Button(intent: ShowNextLinesIntent()) {
                content
                    .padding(.top, Self.tapRoomAbove)
                    .padding(.bottom, Self.tapRoomBelow)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -Self.tapRoomAbove)
            .padding(.bottom, -Self.tapRoomBelow)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("\(pageName), \(Text("Show the next line")), \(Text("\(page.otherLineCount) other lines"))")
            )
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
