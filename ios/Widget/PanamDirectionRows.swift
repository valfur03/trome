import TROMEBadge
import TROMECore
import SwiftUI

struct PanamDirectionRows: View {
    let direction: LineDirection
    let line: TransitLine
    let isStale: Bool
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(direction.trainsByDestination, id: \.self) { branch in
                PanamRow(
                    destination: branch.destination,
                    trains: branch.trains,
                    nextTrainIsOverAnHourAway: direction.nextTrainIsOverAnHourAway,
                    hasNoAnswer: direction.hasNoAnswer,
                    line: line,
                    isStale: isStale,
                    isCompact: isCompact
                )
            }
        }
    }
}

private struct PanamRow: View {
    let destination: String
    let trains: [LineDirection.Train]
    let nextTrainIsOverAnHourAway: Bool
    let hasNoAnswer: Bool
    let line: TransitLine
    let isStale: Bool
    let isCompact: Bool

    var body: some View {
        if trains.count > 1 && !isStale {
            ViewThatFits(in: .horizontal) {
                row(timeCount: 2, fitsTheWholeDestination: true)
                row(timeCount: 1, fitsTheWholeDestination: false)
            }
        } else {
            row(timeCount: 1, fitsTheWholeDestination: false)
        }
    }

    private func row(timeCount: Int, fitsTheWholeDestination: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.caption.bold())
                .foregroundStyle(line.badgeColor)
                .accessibilityHidden(true)
            Text(destination)
                .font(isCompact ? .caption : .subheadline)
                .lineLimit(1)
                .minimumScaleFactor(fitsTheWholeDestination ? 0.85 : 0.7)
                .fixedSize(horizontal: fitsTheWholeDestination, vertical: true)
            Spacer(minLength: 6)
            if trains.isEmpty {
                if !hasNoAnswer && (!nextTrainIsOverAnHourAway || !isStale) {
                    NoTrainsText(nextTrainIsOverAnHourAway: nextTrainIsOverAnHourAway, isCompact: isCompact)
                        .fixedSize()
                }
            } else if !isStale {
                HStack(spacing: 4) {
                    ForEach(Array(trains.prefix(timeCount).enumerated()), id: \.offset) { index, train in
                        PanamWait(train: train, isNext: index == 0, isCompact: isCompact)
                    }
                }
                .fixedSize()
            }
        }
    }
}

private struct PanamWait: View {
    static let amber = Color(red: 1, green: 190.0 / 255, blue: 0)

    let train: LineDirection.Train
    let isNext: Bool
    let isCompact: Bool

    private static let widestMinutes = SystemFormatStyle.DateOffset(
        to: Date(timeIntervalSinceReferenceDate: 59 * 60 + 30),
        allowedFields: [.minute],
        sign: .never
    ).format(Date(timeIntervalSinceReferenceDate: 0))

    var body: some View {
        label
            .font(isNext && !isCompact ? .subheadline.bold() : .caption.bold())
            .fontWidth(.condensed)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Self.amber.opacity(isNext ? 1 : 0.8))
            .padding(.horizontal, 6)
            .background(.black, in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder private var label: some View {
        switch train.status {
        case .approaching:
            Text("Approaching")
        case .atPlatform:
            Text("At the platform")
        case nil:
            Text(Self.widestMinutes)
                .hidden()
                .overlay {
                    Text(
                        .currentDate,
                        format: .offset(to: train.roundedUpCountdownEnd, allowedFields: [.minute], sign: .never)
                    )
                }
        }
    }
}
