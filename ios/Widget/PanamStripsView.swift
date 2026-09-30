import RATPCore
import SwiftUI

struct PanamStripsView: View {
    let state: StationActivityAttributes.ContentState
    let line: LineTrains
    let isStale: Bool

    @ScaledMetric(relativeTo: .title3) private var cellWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if line.directions.isEmpty {
                NoTrainsText()
            }
            ForEach(line.directions, id: \.self) { direction in
                PanamStrip(
                    direction: direction,
                    line: line.line,
                    drawnAt: state.updatedAt,
                    isStale: isStale,
                    cellWidth: cellWidth
                )
            }
            if isStale {
                Text("Open the app for new times.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            SnoozeButtons()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            header(showsColumnTitles: true)
            header(showsColumnTitles: false)
        }
    }

    private func header(showsColumnTitles: Bool) -> some View {
        HStack(spacing: 6) {
            MetroLineBadge(line: line.line, size: .regular)
            Text(state.stationName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(showsColumnTitles ? 1 : 0.7)
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
