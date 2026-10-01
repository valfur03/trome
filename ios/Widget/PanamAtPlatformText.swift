import SwiftUI

struct PanamAtPlatformText: View {
    static let oneLineScales: [CGFloat] = [1, 0.9, 0.8]
    static let oneLineMargin: CGFloat = 2
    static let twoLinesMargin: CGFloat = 3

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 11

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.oneLineScales, id: \.self) { scale in
                Text("At the platform")
                    .font(.system(size: size * scale, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, Self.oneLineMargin)
            }
            Text("At the platform")
                .font(.caption2.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Self.twoLinesMargin)
        }
    }
}
