import TROMECore
import SwiftUI

struct PanamBranchEndRows: View {
    static let nameScales: [CGFloat] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7]
    static let numberFont = Font.subheadline.bold()

    let rows: [BranchEndRow]
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

    private func row(_ row: BranchEndRow, nameScale: CGFloat, isWhole: Bool) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: row.end)
                .font(.system(size: nameSize * nameScale, weight: .bold))
                .foregroundStyle(PanamStrip.plateBlue)
                .lineLimit(1)
                .fixedSize(horizontal: isWhole, vertical: true)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: isStale ? nil : rowHeight, alignment: .leading)
            ZStack {
                box(of: row)
            }
            .frame(width: boxWidth)
            .frame(maxHeight: .infinity)
            .background(.black)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(of: row))
    }

    @ViewBuilder private func box(of row: BranchEndRow) -> some View {
        if !isStale {
            switch row.shown {
            case .trains(let trains):
                HStack(spacing: 0) {
                    cell(trains.first)
                    Rectangle()
                        .fill(.white.opacity(trains.count > 1 ? 0.85 : 0))
                        .frame(width: PanamStrip.ruleWidth)
                        .padding(.vertical, 3)
                    cell(trains.dropFirst().first)
                }
                .frame(height: rowHeight)
            case .notListed:
                HStack(spacing: PanamStrip.ruleWidth) {
                    WaitDash()
                        .font(Self.numberFont)
                        .frame(width: cellWidth)
                    Color.clear
                        .frame(width: cellWidth)
                }
                .frame(height: rowHeight)
            case .overAnHour:
                SielNoTrainBox(nextTrainIsOverAnHourAway: true, isStale: false)
            case .noTrain:
                SielNoTrainBox(nextTrainIsOverAnHourAway: false, isStale: false)
            case .noAnswer:
                Color.clear
                    .frame(height: rowHeight)
            }
        }
    }

    private func accessibilityLabel(of row: BranchEndRow) -> Text {
        let name = Text(verbatim: row.end)
        if isStale {
            return name
        }
        switch row.shown {
        case .trains(let trains):
            return PanamStrip.accessibilityLabel(
                name: row.end,
                trains: trains,
                nextTrainIsOverAnHourAway: false,
                isStale: false
            )
        case .notListed:
            return Text("\(name), \(Text("no train announced"))")
        case .overAnHour:
            return Text("\(name), \(Text("In over 1 hour"))")
        case .noTrain:
            return Text("\(name), \(Text("No trains"))")
        case .noAnswer:
            return name
        }
    }

    private func cell(_ train: LineDirection.Train?) -> some View {
        PanamCell(train: train, drawnAt: drawnAt, numberFont: Self.numberFont, width: cellWidth)
    }

    private var boxWidth: CGFloat {
        cellWidth * 2 + PanamStrip.ruleWidth
    }
}
