import TROMECore
import SwiftUI

struct PanamStripsView: View {
    let state: StationActivityAttributes.ContentState
    let page: LinesPage
    let line: LineTrains
    let isStale: Bool

    @ScaledMetric(relativeTo: .title3) private var cellWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanamStripsHeader(page: page, line: line, stationName: state.stationName, cellWidth: cellWidth)
            if line.directions.isEmpty {
                NoTrainsText()
                    .invalidatableContent()
            }
            ForEach(line.directions, id: \.self) { direction in
                Group {
                    if let rows = direction.branchEndRows {
                        PanamBranchEndRows(
                            rows: rows,
                            line: line.line,
                            drawnAt: state.updatedAt,
                            isStale: isStale,
                            cellWidth: cellWidth
                        )
                    } else {
                        PanamStrip(
                            direction: direction,
                            line: line.line,
                            drawnAt: state.updatedAt,
                            isStale: isStale,
                            cellWidth: cellWidth
                        )
                    }
                }
                .invalidatableContent()
            }
            if isStale {
                Text(staleTimesOf: state)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(Text(spokenStaleTimesOf: state))
                    .invalidatableContent()
            }
            SnoozeButtons()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
