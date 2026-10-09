import TROMECore
import SwiftUI

struct PanamStripsHeader: View {
    static let nameScales: [CGFloat] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6]

    let page: LinesPage
    let line: LineTrains
    let stationName: String
    let cellWidth: CGFloat

    @ScaledMetric(relativeTo: .headline) private var nameSize: CGFloat = 17

    var body: some View {
        LinesPagerButton(page: page, pageName: pageName) {
            ViewThatFits(in: .horizontal) {
                if !page.hasOtherLines {
                    row(showsColumnTitles: true) {
                        oneLineName(scale: 1)
                    }
                }
                ForEach(Self.nameScales, id: \.self) { scale in
                    row(showsColumnTitles: false) {
                        oneLineName(scale: scale)
                    }
                }
                row(showsColumnTitles: false) {
                    name(Text(shownName)
                        .font(nameFont(scale: 1))
                        .lineLimit(line.hasRoomForATwoLineStationName ? 2 : 1)
                        .minimumScaleFactor(Self.nameScales.last ?? 1))
                }
            }
        }
    }

    private var shownName: String {
        line.stationName ?? stationName
    }

    private var pageName: Text {
        guard let otherStation = line.stationName else {
            return Text("\(line.line.localizedName), \(stationName)")
        }
        return Text("\(line.line.localizedName), walk to \(otherStation)")
    }

    private func oneLineName(scale: CGFloat) -> some View {
        name(Text(shownName)
            .font(nameFont(scale: scale))
            .lineLimit(1)
            .minimumScaleFactor(Self.nameScales.last ?? 1))
    }

    @ViewBuilder private func name(_ text: some View) -> some View {
        if line.stationName != nil {
            HStack(spacing: 3) {
                Image(systemName: "figure.walk")
                    .font(.subheadline.bold())
                    .accessibilityHidden(true)
                text
            }
        } else {
            text
        }
    }

    private func nameFont(scale: CGFloat) -> Font {
        .system(size: nameSize * scale, weight: .semibold)
    }

    private func row(showsColumnTitles: Bool, @ViewBuilder name: () -> some View) -> some View {
        HStack(spacing: 6) {
            LineBadge(line: line.line, surface: .header)
            name()
            Spacer(minLength: 4)
            if page.hasOtherLines {
                OtherLinesControl(count: page.otherLineCount)
            } else if showsColumnTitles, line.line.mode == .metro {
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
