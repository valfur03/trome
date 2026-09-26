import ActivityKit
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
                    TrainsSummary(state: context.state, isStale: context.isStale)
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
        VStack(alignment: .leading, spacing: 8) {
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
        }
        .padding()
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
                    .font(.caption)
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
        HStack {
            Image(systemName: "arrow.right")
                .font(.caption)
            Text(direction.label)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if direction.times.isEmpty {
                Text("No trains")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            } else if !isStale {
                VStack(alignment: .trailing, spacing: 0) {
                    WaitingTime(time: direction.times[0])
                        .font(.headline)
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
    StationActivityAttributes.ContentState(stationName: "Abbesses", trains: .noData, updatedAt: .now)
}
