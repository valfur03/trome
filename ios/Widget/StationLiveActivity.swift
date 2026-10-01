import ActivityKit
import RATPCore
import SwiftUI
import WidgetKit

struct StationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StationActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.black)
                .environment(\.colorScheme, .dark)
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
                    ExpandedIslandBottomRegion(state: context.state, isStale: context.isStale)
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

struct LockScreenView: View {
    let state: StationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if let page = state.trains.linesPage, let line = page.panamStripsLine {
            PanamStripsView(state: state, page: page, line: line, isStale: isStale)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                if let page = state.multiLinePage {
                    StationAndLinesHeader(stationName: state.stationName, page: page)
                } else if let line = state.leadingLine, line.mode == .metro {
                    MetroLineBadge(line: line, size: .regular)
                    Text(state.stationName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                } else {
                    Image(systemName: state.leadingLine?.symbolName ?? "tram.fill")
                        .font(.headline)
                        .accessibilityHidden(true)
                    Text(state.stationName)
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

struct ExpandedIslandBottomRegion: View {
    let state: StationActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            ExpandedIslandBottom(state: state, isStale: isStale)
            ExpandedIslandBottom(state: state.keepingOnlyTheNextTrains, isStale: isStale)
            ExpandedIslandBottom(state: state.keepingOnlyTheNextTrains, isStale: isStale, isCompact: true)
        }
    }
}

private struct ExpandedIslandBottom: View {
    static let cornerRoom: CGFloat = 8

    let state: StationActivityAttributes.ContentState
    let isStale: Bool
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let page = state.multiLinePage {
                StationAndLinesHeader(stationName: state.stationName, page: page, isCompact: isCompact)
            }
            TrainsSummary(state: state, isStale: isStale, isCompact: isCompact)
            SnoozeButtons()
        }
        .padding(.bottom, Self.cornerRoom)
    }

    private var spacing: CGFloat {
        if isCompact { return 2 }
        return state.multiLinePage == nil ? 8 : 4
    }
}

private struct StationAndLinesHeader: View {
    let stationName: String
    let page: LinesPage
    var isCompact = false

    var body: some View {
        LinesPagerButton(page: page, pageName: pageName) {
            HStack(alignment: .center) {
                Text(stationName)
                    .font(isCompact ? .subheadline.bold() : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if page.hasOtherLines {
                    OtherLinesControl(count: page.otherLineCount)
                }
            }
        }
    }

    private var pageName: Text {
        Text(verbatim: (page.lines.map(\.line.localizedName) + [stationName]).joined(separator: ", "))
    }
}

private struct TrainsSummary: View {
    let state: StationActivityAttributes.ContentState
    let isStale: Bool
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
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
                    LineTrainsView(line: line, isStale: isStale, isCompact: isCompact)
                }
            case .lines(let page):
                ForEach(page.lines, id: \.self) { line in
                    if line.hasNoTrain {
                        NoTrainsText(isCompact: isCompact)
                    } else {
                        ForEach(line.directions, id: \.self) { direction in
                            LineDirectionRow(
                                direction: direction,
                                line: line.line,
                                isStale: isStale,
                                isCompact: isCompact
                            )
                        }
                    }
                }
            }
            if isStale {
                Text("Open the app for new times.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .invalidatableContent()
    }
}

private struct LineTrainsView: View {
    let line: LineTrains
    let isStale: Bool
    var isCompact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SmallLineBadge(line: line.line)
            VStack(alignment: .leading, spacing: 0) {
                if let stationName = line.stationName {
                    ServingStationName(name: stationName)
                }
                if line.hasNoTrain {
                    NoTrainsText(isCompact: isCompact)
                } else {
                    ForEach(line.directions, id: \.self) { direction in
                        LineDirectionRow(direction: direction, line: line.line, isStale: isStale, isCompact: isCompact)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LineDirectionRow: View {
    let direction: LineDirection
    let line: TransitLine
    let isStale: Bool
    var isCompact = false

    var body: some View {
        switch line.mode {
        case .metro:
            PanamDirectionRows(direction: direction, line: line, isStale: isStale, isCompact: isCompact)
        case .rer:
            RERDirectionRow(direction: direction, isStale: isStale, isCompact: isCompact)
        }
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
