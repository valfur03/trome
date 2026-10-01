import RATPCore
import SwiftUI

struct CompactIslandWait: View {
    static let wordFont = Font.caption2.bold()
    static let noTrainsWidth: CGFloat = 44
    static let wordMaximumWidth: CGFloat = 52
    static let markGap: CGFloat = 2

    let island: DynamicIslandWait
    let drawnAt: Date

    var body: some View {
        HStack(spacing: Self.markGap) {
            if let mark = island.branchEndIndex {
                PanamBranchMark(index: mark)
            }
            wait
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(island.spokenWait)
    }

    @ViewBuilder private var wait: some View {
        switch island.wait {
        case .minutes(let train):
            IslandNumber(value: .minutes(train), drawnAt: drawnAt)
        case .approaching:
            IslandNumber(value: .zero, drawnAt: drawnAt)
        case .atPlatform:
            IslandWordLayout(maximumWidth: Self.wordMaximumWidth) {
                word(Text("At the platform"), color: PanamStrip.amber, lines: 2)
                    .multilineTextAlignment(.trailing)
            }
        case .overAnHour:
            word(Text("> 1 h"), color: PanamStrip.amber)
        case .noTrain:
            word(Text("No trains"), color: .secondary, lines: 2)
                .multilineTextAlignment(.center)
                .frame(width: Self.noTrainsWidth)
        case .stale, .loading, .noData:
            IslandNumber(value: .dash, drawnAt: drawnAt)
        }
    }

    private func word(_ text: Text, color: Color, lines: Int = 1) -> some View {
        text
            .font(Self.wordFont)
            .foregroundStyle(color)
            .lineLimit(lines)
    }
}
