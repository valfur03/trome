import RATPCore
import SwiftUI

struct SielRowsView: View {
    let state: StationActivityAttributes.ContentState
    let page: LinesPage
    let line: LineTrains
    let isStale: Bool

    @ScaledMetric(relativeTo: .title3) private var cellWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanamStripsHeader(page: page, line: line, stationName: state.stationName, cellWidth: cellWidth)
            VStack(alignment: .leading, spacing: 3) {
                if line.directions.isEmpty {
                    NoTrainsText()
                }
                ForEach(line.directions, id: \.self) { direction in
                    SielPlate(line: line.line) {
                        rows(of: direction)
                    }
                }
            }
            .invalidatableContent()
            if isStale {
                Text("Open the app for new times.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .invalidatableContent()
            }
            SnoozeButtons()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func rows(of direction: LineDirection) -> some View {
        if direction.trains.isEmpty || isStale {
            SielRow(
                destination: direction.name,
                spokenState: spokenStateWithoutTrains(of: direction),
                boxWidth: boxWidth
            ) {
                if direction.trains.isEmpty {
                    SielNoTrainBox(nextTrainIsOverAnHourAway: direction.nextTrainIsOverAnHourAway, isStale: isStale)
                }
            }
        } else {
            ForEach(Array(direction.trains.enumerated()), id: \.offset) { index, train in
                if index > 0 {
                    SielRule(boxWidth: boxWidth)
                }
                SielRow(destination: train.destination, spokenState: SielWait.spoken(train), boxWidth: boxWidth) {
                    SielWait(train: train, drawnAt: state.updatedAt)
                }
            }
        }
    }

    private func spokenStateWithoutTrains(of direction: LineDirection) -> Text? {
        guard direction.trains.isEmpty else { return nil }
        if direction.nextTrainIsOverAnHourAway {
            return isStale ? nil : Text("In over 1 hour")
        }
        return Text("No trains")
    }

    private var boxWidth: CGFloat {
        cellWidth * 2 + PanamStrip.ruleWidth
    }
}

private struct SielPlate<Content: View>: View {
    let line: TransitLine
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(line.badgeColor)
                .frame(width: 5)
            VStack(spacing: 0) {
                content
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SielRule: View {
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
