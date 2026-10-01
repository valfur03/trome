import SwiftUI

struct PanamBranchEnds: View {
    static let scales: [CGFloat] = [0.73]
    static let floorScale: CGFloat = 0.7

    let ends: [String]

    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 15

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.scales, id: \.self) { scale in
                endsList(textSize: textSize * scale, isWhole: true)
            }
            endsList(textSize: textSize * Self.floorScale, isWhole: false)
        }
    }

    private func endsList(textSize: CGFloat, isWhole: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ends.enumerated()), id: \.offset) { index, end in
                HStack(spacing: 3) {
                    PanamBranchMark(index: index)
                    Text(verbatim: end)
                        .font(.system(size: textSize, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: isWhole, vertical: false)
                }
            }
        }
    }
}
