import SwiftUI

struct PanamBranchMark: View {
    static let colors = [
        Color(red: 1, green: 223 / 255, blue: 0),
        Color(red: 0, green: 159 / 255, blue: 227 / 255)
    ]
    static let circleShare: CGFloat = 5.0 / 7

    let index: Int

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 7

    var body: some View {
        let diameter = size * Self.circleShare
        Group {
            if index == 0 {
                Circle()
                    .fill(Self.colors[0])
                    .frame(width: diameter, height: diameter)
            } else {
                let side = diameter * (Double.pi / 4).squareRoot()
                Rectangle()
                    .fill(Self.colors[1])
                    .frame(width: side, height: side)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
