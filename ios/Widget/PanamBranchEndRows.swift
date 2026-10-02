import RATPCore
import SwiftUI

struct PanamBranchEndRows: View {
    static let nameScales: [CGFloat] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7]

    let rows: [BranchEndTrains]
    let line: TransitLine
    let drawnAt: Date
    let isStale: Bool
    let cellWidth: CGFloat

    @ScaledMetric(relativeTo: .footnote) private var nameSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 18.5

    var body: some View {
        SielPlate(line: line) {
            ViewThatFits(in: .horizontal) {
                ForEach(Self.nameScales, id: \.self) { scale in
                    group(nameScale: scale, isWhole: true)
                }
                group(nameScale: Self.nameScales.last ?? 1, isWhole: false)
            }
        }
    }

    private func group(nameScale: CGFloat, isWhole: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    SielRule(boxWidth: boxWidth)
                }
                self.row(row, nameScale: nameScale, isWhole: isWhole)
            }
        }
    }

    private func row(_ row: BranchEndTrains, nameScale: CGFloat, isWhole: Bool) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: row.end)
                .font(.system(size: nameSize * nameScale, weight: .bold))
                .foregroundStyle(PanamStrip.plateBlue)
                .lineLimit(1)
                .fixedSize(horizontal: isWhole, vertical: true)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: isStale ? nil : rowHeight, alignment: .leading)
            box(of: row)
                .frame(width: boxWidth)
                .frame(maxHeight: .infinity)
                .background(.black)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PanamStrip.accessibilityLabel(
            name: row.end,
            trains: row.trains,
            nextTrainIsOverAnHourAway: row.nextTrainIsOverAnHourAway,
            isStale: isStale
        ))
    }

    @ViewBuilder private func box(of row: BranchEndTrains) -> some View {
        if row.trains.isEmpty {
            SielNoTrainBox(nextTrainIsOverAnHourAway: row.nextTrainIsOverAnHourAway, isStale: isStale)
        } else if !isStale {
            HStack(spacing: 0) {
                cell(row.trains.first)
                Rectangle()
                    .fill(.white.opacity(row.trains.count > 1 ? 0.85 : 0))
                    .frame(width: PanamStrip.ruleWidth)
                    .padding(.vertical, 3)
                cell(row.trains.dropFirst().first)
            }
            .frame(height: rowHeight)
        }
    }

    private func cell(_ train: LineDirection.Train?) -> some View {
        PanamCell(train: train, drawnAt: drawnAt, numberFont: .subheadline.bold(), width: cellWidth)
    }

    private var boxWidth: CGFloat {
        cellWidth * 2 + PanamStrip.ruleWidth
    }
}
