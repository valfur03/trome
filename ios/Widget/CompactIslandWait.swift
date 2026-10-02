import RATPCore
import SwiftUI

struct CompactIslandWait: View {
    static let wordFont = Font.system(size: 11, weight: .bold)
    static let noTrainsWidth: CGFloat = 44
    static let wordMaximumWidth: CGFloat = 60
    static let wordMinimumScale: CGFloat = 0.8
    static let wrappedWordCornerInset: CGFloat = 4

    let island: DynamicIslandWait
    let drawnAt: Date

    var body: some View {
        wait
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
            IslandWordLayout(maximumWidth: Self.wordMaximumWidth, wrappedCornerInset: Self.wrappedWordCornerInset) {
                word(Text("At the platform"), color: PanamStrip.amber, lines: 2)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(Self.wordMinimumScale)
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
