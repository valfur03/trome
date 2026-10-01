import RATPCore
import SwiftUI

struct PanamStripsHeader: View {
    static let nameScales: [CGFloat] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6]

    let line: TransitLine
    let stationName: String
    let cellWidth: CGFloat
    let wrapsALongName: Bool

    @ScaledMetric(relativeTo: .headline) private var nameSize: CGFloat = 17

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsColumnTitles: true) {
                oneLineName(scale: 1)
            }
            ForEach(Self.nameScales, id: \.self) { scale in
                row(showsColumnTitles: false) {
                    oneLineName(scale: scale)
                }
            }
            row(showsColumnTitles: false) {
                Text(stationName)
                    .font(nameFont(scale: 1))
                    .lineLimit(wrapsALongName ? 2 : 1)
                    .minimumScaleFactor(Self.nameScales.last ?? 1)
            }
        }
    }

    private func oneLineName(scale: CGFloat) -> some View {
        Text(stationName)
            .font(nameFont(scale: scale))
            .lineLimit(1)
    }

    private func nameFont(scale: CGFloat) -> Font {
        .system(size: nameSize * scale, weight: .semibold)
    }

    private func row(showsColumnTitles: Bool, @ViewBuilder name: () -> some View) -> some View {
        HStack(spacing: 6) {
            MetroLineBadge(line: line, size: .regular)
            name()
            Spacer(minLength: 4)
            if showsColumnTitles {
                HStack(spacing: PanamStrip.ruleWidth) {
                    Text("1st")
                        .frame(width: cellWidth)
                    Text("2nd")
                        .frame(width: cellWidth)
                }
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
    }
}
