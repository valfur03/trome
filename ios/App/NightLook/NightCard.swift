import SwiftUI

struct NightCard<Content: View>: View {
    var isProblem = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(NightLook.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(NightLook.text)
        .background(NightLook.card, in: shape)
        .overlay {
            if isProblem {
                shape.strokeBorder(NightLook.problem, lineWidth: NightLook.problemBorder)
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NightLook.cardCorner, style: .continuous)
    }
}
