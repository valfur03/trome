import SwiftUI

struct NightPlate<Content: View>: View {
    var isProblem = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(NightLook.platePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(NightLook.plate, in: shape)
        .overlay {
            shape.strokeBorder(
                isProblem ? NightLook.problem : .white.opacity(0.12),
                lineWidth: isProblem ? NightLook.problemBorder : 1
            )
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NightLook.plateCorner, style: .continuous)
    }
}
