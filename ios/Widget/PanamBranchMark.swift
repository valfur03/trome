import SwiftUI

struct PanamBranchMark: View {
    static let colors = [Color(red: 0.12, green: 0.36, blue: 1), Color(red: 0.05, green: 0.65, blue: 0.3)]

    let index: Int

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 7

    var body: some View {
        Group {
            if index == 0 {
                Circle()
                    .fill(Self.colors[0])
            } else {
                Rectangle()
                    .fill(Self.colors[1])
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
