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
                    if context.state.multiLinePage == nil {
                        Image(systemName: context.state.leadingLine?.symbolName ?? "tram.fill")
                            .font(.title3)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.multiLinePage == nil {
                        Text(context.state.stationName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: context.state.multiLinePage == nil ? 8 : 4) {
                        if let page = context.state.multiLinePage {
                            StationAndLinesHeader(stationName: context.state.stationName, page: page)
                        }
                        TrainsSummary(state: context.state, isStale: context.isStale)
                        SnoozeButtons()
                    }
                }
            } compactLeading: {
                if let line = context.state.leadingLine {
                    Label(line.name, systemImage: line.symbolName)
                        .font(.caption.bold())
                } else {
                    Image(systemName: "tram.fill")
                }
            } compactTrailing: {
                if !context.isStale, let time = context.state.nextTime {
                    WaitingTime(time: time)
                        .font(.caption.bold())
                } else if !context.isStale, context.state.trains.linesPage?.nextTrainIsOverAnHourAway == true {
                    Text("> 1 h")
                        .font(.caption.bold())
                        .accessibilityLabel("Next train in over 1 hour")
                } else {
                    Image(systemName: "exclamationmark.circle")
                }
            } minimal: {
                Image(systemName: context.state.leadingLine?.symbolName ?? "tram.fill")
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
                if let page = state.multiLinePage {
                    StationAndLinesHeader(stationName: state.stationName, page: page)
                } else {
                    Label(state.stationName, systemImage: state.leadingLine?.symbolName ?? "tram.fill")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if let line = state.leadingLine {
                        LineBadge(line: line)
                    }
                }
            }
            TrainsSummary(state: state, isStale: isStale)
            SnoozeButtons()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

private struct StationAndLinesHeader: View {
    let stationName: String
    let page: LinesPage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            header(showsEveryBadge: true)
            header(showsEveryBadge: false)
        }
    }

    private func header(showsEveryBadge: Bool) -> some View {
        HStack {
            Text(stationName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            LinesPager(page: page, showsEveryBadge: showsEveryBadge)
        }
    }
}

private struct LinesPager: View {
    let page: LinesPage
    let showsEveryBadge: Bool

    var body: some View {
        if page.hasOtherLines {
            Button(intent: ShowNextLinesIntent()) {
                HStack(spacing: 3) {
                    badges
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the next lines")
        } else {
            badges
        }
    }

    private var badges: some View {
        HStack(spacing: 3) {
            if showsEveryBadge {
                ForEach(page.allLines, id: \.self) { line in
                    SmallLineBadge(line: line, isShown: page.isShown(line))
                }
            } else {
                ForEach(page.lines.map(\.line), id: \.self) { line in
                    SmallLineBadge(line: line, isShown: true)
                }
                if page.otherLineCount > 0 {
                    OtherLinesBadge(count: page.otherLineCount)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.allLines.map(\.localizedName).joined(separator: ", "))
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

    private func title(of duration: SnoozeDuration) -> LocalizedStringKey {
        switch duration {
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 h"
        case .restOfToday: "Today"
        }
    }

    private func accessibilityTitle(of duration: SnoozeDuration) -> LocalizedStringKey {
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
            case .lines(let page) where page.showsSeveralLines:
                ForEach(page.lines, id: \.self) { line in
                    LineTrainsView(line: line, isStale: isStale)
                }
            case .lines(let page):
                ForEach(page.lines.flatMap(\.directions), id: \.self) { direction in
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

private struct LineTrainsView: View {
    let line: LineTrains
    let isStale: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SmallLineBadge(line: line.line, isShown: true)
            VStack(alignment: .leading, spacing: 0) {
                if let stationName = line.stationName {
                    ServingStationName(name: stationName)
                }
                if line.directions.isEmpty {
                    Text("No trains")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(line.directions, id: \.self) { direction in
                        DirectionRow(direction: direction, isStale: isStale)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DirectionRow: View {
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
                    Text(direction.nextTrainIsOverAnHourAway ? "In over 1 hour" : "No trains")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

private extension StationActivityAttributes.ContentState {
    var leadingLine: TransitLine? {
        guard let page = trains.linesPage else { return nil }
        return page.soonestTrain?.line ?? page.allLines.first
    }

    var nextTime: Date? {
        trains.linesPage?.soonestTrain?.time
    }

    var multiLinePage: LinesPage? {
        trains.linesPage.flatMap { $0.showsSeveralLines ? $0 : nil }
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
