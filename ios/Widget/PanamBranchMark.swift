import SwiftUI

struct PanamBranchMark: View {
    static let colors = [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.85, green: 0.4, blue: 0)]

    let index: Int

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 7

    var body: some View {
        Group {
            if index == 0 {
                Circle()
                    .fill(Self.colors[0])
            } else {
                Triangle()
                    .fill(Self.colors[1])
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
