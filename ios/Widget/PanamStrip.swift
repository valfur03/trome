import TROMECore
import SwiftUI

struct PanamStrip: View {
    static let ruleWidth: CGFloat = 1
    static let amber = Color(red: 1, green: 190.0 / 255, blue: 0)
    static let plateBlue = Color(red: 0.06, green: 0.1, blue: 0.47)

    let direction: LineDirection
    let line: TransitLine
    let drawnAt: Date
    let isStale: Bool
    let cellWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(line.badgeColor)
                .frame(width: 5)
            Text(direction.name)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Self.plateBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            screen
                .frame(width: cellWidth * 2 + Self.ruleWidth)
                .frame(maxHeight: .infinity)
                .background(.black)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(
            name: direction.name,
            trains: direction.trains,
            nextTrainIsOverAnHourAway: direction.nextTrainIsOverAnHourAway,
            isStale: isStale
        ))
    }

    @ViewBuilder private var screen: some View {
        let trains = direction.trains
        ZStack {
            if !isStale {
                Text(verbatim: "00")
                    .font(.title3.bold())
                    .padding(.vertical, 4)
                    .hidden()
            }
            if trains.isEmpty {
                if !direction.nextTrainIsOverAnHourAway {
                    message("No trains", color: .secondary)
                } else if !isStale {
                    message("> 1 h", color: Self.amber)
                }
            } else if !isStale {
                HStack(spacing: 0) {
                    cell(trains.first)
                    Rectangle()
                        .fill(.white.opacity(trains.count > 1 ? 0.85 : 0))
                        .frame(width: Self.ruleWidth)
                        .padding(.vertical, 6)
                    cell(trains.dropFirst().first)
                }
            }
        }
    }

    private func message(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
    }

    private func cell(_ train: LineDirection.Train?) -> some View {
        PanamCell(train: train, drawnAt: drawnAt, numberFont: .title3.bold(), width: cellWidth)
    }

    static func accessibilityLabel(
        name: String,
        trains: [LineDirection.Train],
        nextTrainIsOverAnHourAway: Bool,
        isStale: Bool
    ) -> Text {
        let name = Text(verbatim: name)
        if isStale {
            return name
        }
        guard let first = trains.first else {
            let state: Text = nextTrainIsOverAnHourAway ? Text("In over 1 hour") : Text("No trains")
            return Text("\(name), \(state)")
        }
        guard let second = trains.dropFirst().first else {
            return Text("\(name), \(PanamCell.spoken(first))")
        }
        return Text("\(name), \(PanamCell.spoken(first)), then \(PanamCell.spoken(second))")
    }
}
