import SwiftUI

struct SielRule: View {
    let boxWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(PanamStrip.plateBlue.opacity(0.18))
            Rectangle()
                .fill(.white.opacity(0.3))
                .padding(.horizontal, 6)
                .frame(width: boxWidth)
                .background(.black)
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}
