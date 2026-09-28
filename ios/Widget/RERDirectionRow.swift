import RATPCore
import SwiftUI

struct RERDirectionRow: View {
    let direction: LineDirection
    let isStale: Bool
    var isCompact = false

    var body: some View {
        if direction.showsEachDestination && !isStale {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(direction.trains.enumerated()), id: \.offset) { index, train in
                    TrainRow(train: train, isNext: index == 0)
                }
            }
        } else {
            HStack {
                Image(systemName: "arrow.right")
                    .font(.caption)
                DirectionName(text: direction.name)
                    .font(isCompact ? .caption : .subheadline)
                Spacer(minLength: 8)
                if direction.times.isEmpty {
                    if !direction.nextTrainIsOverAnHourAway || !isStale {
                        NoTrainsText(
                            nextTrainIsOverAnHourAway: direction.nextTrainIsOverAnHourAway,
                            isCompact: isCompact
                        )
                        .layoutPriority(1)
                    }
                } else if !isStale {
                    VStack(alignment: .trailing, spacing: 0) {
                        WaitingTime(time: direction.times[0])
                            .font(isCompact ? .caption.bold() : .subheadline.bold())
                        if direction.times.count > 1 {
                            WaitingTime(time: direction.times[1])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: WaitingTime.minimumWidth, alignment: .trailing)
                }
            }
        }
    }
}

private struct TrainRow: View {
    let train: LineDirection.Train
    let isNext: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "arrow.right")
                .font(.caption)
                .opacity(isNext ? 1 : 0)
            DirectionName(text: train.destination)
                .font(isNext ? .subheadline : .caption)
                .foregroundStyle(isNext ? .primary : .secondary)
            Spacer(minLength: 8)
            WaitingTime(time: train.time)
                .font(isNext ? .subheadline.bold() : .caption2)
                .foregroundStyle(isNext ? .primary : .secondary)
                .frame(minWidth: WaitingTime.minimumWidth, alignment: .trailing)
        }
    }
}

private struct DirectionName: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .layoutPriority(1)
    }
}
