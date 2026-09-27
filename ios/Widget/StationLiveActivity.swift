import ActivityKit
import AppIntents
import RATPCore
import SwiftUI
import WidgetKit

struct StationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StationActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.line?.symbolName ?? "tram.fill")
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stationName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        TrainsSummary(state: context.state, isStale: context.isStale)
                        SnoozeButtons()
                    }
                }
            } compactLeading: {
                if let line = context.state.line {
                    Label(line.name, systemImage: line.symbolName)
                        .font(.caption.bold())
                } else {
                    Image(systemName: "tram.fill")
                }
            } compactTrailing: {
                if !context.isStale, let time = context.state.nextTime {
                    WaitingTime(time: time)
                        .font(.caption.bold())
                } else {
                    Image(systemName: "exclamationmark.circle")
                }
            } minimal: {
                Image(systemName: context.state.line?.symbolName ?? "tram.fill")
            }
        }
    }
}

private struct LockScreenView: View {
    let state: StationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(state.stationName, systemImage: state.line?.symbolName ?? "tram.fill")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let line = state.line {
                    LineBadge(line: line)
                }
            }
            TrainsSummary(state: state, isStale: isStale)
            SnoozeButtons()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

private struct SnoozeButtons: View {
    var body: some View {
        HStack(spacing: 6) {
            Label("Snooze", systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                Button(intent: SnoozeLiveActivityIntent(duration: duration)) {
                    Text(title(of: duration))
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .accessibilityLabel(accessibilityTitle(of: duration))
            }
        }
    }

    private func title(of duration: SnoozeDuration) -> String {
        switch duration {
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 h"
        case .restOfToday: "Today"
        }
    }

    private func accessibilityTitle(of duration: SnoozeDuration) -> String {
        switch duration {
        case .thirtyMinutes: "Snooze for 30 minutes"
        case .oneHour: "Snooze for 1 hour"
        case .restOfToday: "Snooze for the rest of today"
        }
    }
}

private struct TrainsSummary: View {
    let state: StationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch state.trains {
            case .loading:
                if !isStale {
                    Text("Loading the next trains…")
                        .foregroundStyle(.secondary)
                }
            case .noData:
                Text("No data available")
                    .font(.subheadline.bold())
                Text("No train times for this station right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .directions(_, let directions):
                ForEach(directions, id: \.self) { direction in
                    DirectionRow(direction: direction, isStale: isStale)
                }
            }
            if isStale {
                Text("Open the app for new times.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DirectionRow: View {
    static let minimumTimeWidth: CGFloat = 112

    let direction: LineDirection
    let isStale: Bool

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
                    .font(.subheadline)
                Spacer(minLength: 8)
                if direction.times.isEmpty {
                    Text("No trains")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                } else if !isStale {
                    VStack(alignment: .trailing, spacing: 0) {
                        WaitingTime(time: direction.times[0])
                            .font(.subheadline.bold())
                        if direction.times.count > 1 {
                            WaitingTime(time: direction.times[1])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: Self.minimumTimeWidth, alignment: .trailing)
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
                .frame(minWidth: DirectionRow.minimumTimeWidth, alignment: .trailing)
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

private struct LineBadge: View {
    let line: TransitLine

    var body: some View {
        Text(line.displayName)
            .font(.subheadline.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

private struct WaitingTime: View {
    let time: Date

    var body: some View {
        Text(.currentDate, format: .reference(to: time, allowedFields: [.minute]))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

private extension StationActivityAttributes.ContentState {
    var line: TransitLine? {
        guard case .directions(let line, _) = trains else { return nil }
        return line
    }

    var nextTime: Date? {
        guard case .directions(_, let directions) = trains else { return nil }
        return directions.compactMap(\.times.first).min()
    }
}

private extension TransitLine {
    var symbolName: String {
        switch mode {
        case .metro: "tram.fill"
        case .rer: "train.side.front.car"
        }
    }
}

#Preview("Lock screen", as: .content, using: StationActivityAttributes()) {
    StationLiveActivity()
} contentStates: {
    StationActivityAttributes.ContentState(
        stationName: "Abbesses",
        trains: .directions(line: TransitLine(mode: .metro, name: "12"), [
            LineDirection(
                label: "Mairie d'Aubervilliers",
                times: [.now.addingTimeInterval(180), .now.addingTimeInterval(540)]
            ),
            LineDirection(label: "Mairie d'Issy", times: [.now.addingTimeInterval(60)])
        ]),
        updatedAt: .now
    )
    StationActivityAttributes.ContentState(
        stationName: "Abbesses",
        trains: .directions(line: TransitLine(mode: .metro, name: "12"), [
            LineDirection(label: "Mairie d'Aubervilliers", times: []),
            LineDirection(label: "Mairie d'Issy", times: [.now.addingTimeInterval(240)])
        ]),
        updatedAt: .now
    )
    StationActivityAttributes.ContentState(
        stationName: "Place de Clichy",
        trains: .directions(line: TransitLine(mode: .metro, name: "13"), [
            LineDirection(label: "Saint-Denis - Université / Asnières - Gennevilliers - Les Courtilles", trains: [
                LineDirection.Train(
                    time: .now.addingTimeInterval(60),
                    destination: "Asnières - Gennevilliers - Les Courtilles"
                ),
                LineDirection.Train(time: .now.addingTimeInterval(300), destination: "Saint-Denis - Université")
            ]),
            LineDirection(label: "Châtillon - Montrouge", times: [.now.addingTimeInterval(120)])
        ]),
        updatedAt: .now
    )
    StationActivityAttributes.ContentState(stationName: "Abbesses", trains: .noData, updatedAt: .now)
}
