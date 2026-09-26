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
                    Image(systemName: context.state.nextRow?.line.symbolName ?? "tram.fill")
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
                if let row = context.state.nextRow {
                    Label(row.line.name, systemImage: row.line.symbolName)
                        .font(.caption.bold())
                } else {
                    Image(systemName: "tram.fill")
                }
            } compactTrailing: {
                if !context.isStale, let time = context.state.nextRow?.times.first {
                    WaitingTime(time: time)
                        .font(.caption.bold())
                } else {
                    Image(systemName: "exclamationmark.circle")
                }
            } minimal: {
                Image(systemName: context.state.nextRow?.line.symbolName ?? "tram.fill")
            }
        }
    }
}

private struct LockScreenView: View {
    let state: StationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(state.stationName, systemImage: state.nextRow?.line.symbolName ?? "tram.fill")
                .font(.headline)
                .lineLimit(1)
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
            case .departures(let rows):
                ForEach(rows, id: \.self) { row in
                    HStack {
                        LineBadge(line: row.line)
                        Text(row.destination)
                            .lineLimit(1)
                        Spacer()
                        if !isStale, let time = row.times.first {
                            WaitingTime(time: time)
                                .font(.title3.bold())
                        }
                    }
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
    var nextRow: StationActivityAttributes.DepartureRow? {
        guard case .departures(let rows) = trains else { return nil }
        return rows.first
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
        trains: .departures([
            .init(
                line: TransitLine(mode: .metro, name: "12"),
                destination: "Mairie d'Issy",
                times: [.now.addingTimeInterval(180), .now.addingTimeInterval(540)]
            )
        ]),
        updatedAt: .now
    )
    StationActivityAttributes.ContentState(stationName: "Abbesses", trains: .noData, updatedAt: .now)
}
