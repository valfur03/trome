import ActivityKit
import TROMECore
import SwiftUI
import WidgetKit

struct StationLiveActivity: Widget {
    /// The system clips the compact leading region with the round end of the island, which cuts the corners of a
    /// square RER badge but not a metro circle. This inset keeps the square whole: the island grows by twice the inset.
    private static let rerIslandInset: CGFloat = 3

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StationActivityAttributes.self) { context in
            LockScreenView(state: context.drawnState, isStale: context.looksStale)
                .activityBackgroundTint(.black)
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.drawnState.multiLinePage == nil {
                        Image(systemName: context.drawnState.leadingLine?.symbolName ?? "tram.fill")
                            .font(.title3)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.drawnState.multiLinePage == nil {
                        Text(context.drawnState.stationName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedIslandBottomRegion(state: context.drawnState, isStale: context.looksStale)
                }
            } compactLeading: {
                if let line = context.island.line {
                    LineBadge(line: line, surface: .compactIsland)
                        .padding(.leading, line.mode == .rer ? Self.rerIslandInset : 0)
                }
            } compactTrailing: {
                CompactIslandWait(island: context.island, drawnAt: context.drawnState.updatedAt)
            } minimal: {
                MinimalIslandWait(island: context.island, drawnAt: context.drawnState.updatedAt)
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
        } else if let page = state.trains.linesPage, let line = page.sielRowsLine {
            SielRowsView(state: state, page: page, line: line, isStale: isStale)
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                if let page = state.multiLinePage {
                    StationAndLinesHeader(stationName: state.stationName, page: page)
                } else if let line = state.leadingLine {
                    LineBadge(line: line, surface: .header)
                    Text(state.stationName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                } else {
                    Image(systemName: "tram.fill")
                        .font(.headline)
                        .accessibilityHidden(true)
                    Text(state.stationName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .zIndex(1)
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
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Loading the next trains…"))
                }
            case .noData where state.appNeedsUpdate:
                Text.updateTheApp
                    .font(.subheadline.bold())
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(Text.spokenUpdateTheApp)
            case .noData:
                Text.timesUnavailable
                    .font(.subheadline.bold())
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(Text.spokenTimesUnavailable)
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
            if isStale, !saysTimesAreUnavailable {
                Text(staleTimesOf: state)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(spokenStaleTimesOf: state))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .invalidatableContent()
    }

    private var saysTimesAreUnavailable: Bool {
        state.trains == .noData && (state.serverIsOut || state.appNeedsUpdate)
    }
}

private struct LineTrainsView: View {
    let line: LineTrains
    let isStale: Bool
    var isCompact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            LineBadge(line: line.line, surface: .lineRow)
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

private extension ActivityViewContext<StationActivityAttributes> {
    /// The content on the page that the rider tapped to, which a push of the server, sent to every rider of the
    /// station with the first page shown, carries but does not show.
    var drawnState: StationActivityAttributes.ContentState {
        state.showingThePage(chosenBy: LinesPageChoiceStore.ofThisApp()?.load(), activityID: activityID)
    }

    var looksStale: Bool {
        state.isStale(systemSaysStale: isStale)
    }

    var island: DynamicIslandWait {
        drawnState.dynamicIslandWait(isStale: looksStale)
    }
}

private extension StationActivityAttributes.ContentState {
    var leadingLine: TransitLine? {
        guard let page = trains.linesPage else { return nil }
        return page.soonestTrain?.line ?? page.allLines.first
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
