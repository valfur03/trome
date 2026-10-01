import RATPCore
import SwiftUI

struct SielRow<Box: View>: View {
    let destination: String
    let spokenState: Text?
    let boxWidth: CGFloat
    @ViewBuilder let box: Box

    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 18.5

    var body: some View {
        HStack(spacing: 0) {
            Text(destination)
                .font(.footnote.bold())
                .foregroundStyle(PanamStrip.plateBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
            ZStack {
                box
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: rowHeight)
            .frame(width: boxWidth)
            .frame(maxHeight: .infinity)
            .background(.black)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        guard let spokenState else { return Text(verbatim: destination) }
        return Text("\(Text(verbatim: destination)), \(spokenState)")
    }
}

struct SielWait: View {
    let train: LineDirection.Train
    let drawnAt: Date

    var body: some View {
        Group {
            switch train.status {
            case .approaching:
                SielWord(word: "Approaching")
            case .atPlatform:
                SielWord(word: "At the platform")
            case nil:
                PanamMinutes(train: train, drawnAt: drawnAt)
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }
        }
        .foregroundStyle(PanamStrip.amber)
    }

    static func spoken(_ train: LineDirection.Train) -> Text {
        switch train.status {
        case .approaching:
            Text("Approaching")
        case .atPlatform:
            Text("At the platform")
        case nil:
            Text(.currentDate, format: .offset(to: train.roundedUpCountdownEnd, allowedFields: [.minute], sign: .never))
        }
    }
}

private struct SielWord: View {
    let word: LocalizedStringKey

    @ScaledMetric(relativeTo: .caption2) private var smallestSize: CGFloat = 10

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(fonts.enumerated()), id: \.offset) { _, font in
                WidestWordLayout {
                    Text(word)
                    Text("Approaching").hidden()
                    Text("At the platform").hidden()
                }
                .font(font)
                .lineLimit(1)
                .padding(.horizontal, 3)
            }
        }
    }

    private var fonts: [Font] {
        [.footnote.bold(), .caption.bold(), .caption2.bold(), .system(size: smallestSize, weight: .bold)]
    }
}

private struct WidestWordLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let shown = sizes.first ?? .zero
        let widest = sizes.map(\.width).max() ?? 0
        return CGSize(width: proposal.width == nil ? widest : shown.width, height: shown.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
        }
    }
}

struct SielNoTrainBox: View {
    let nextTrainIsOverAnHourAway: Bool
    let isStale: Bool

    var body: some View {
        if !nextTrainIsOverAnHourAway {
            message("No trains", color: .secondary)
        } else if !isStale {
            ViewThatFits(in: .horizontal) {
                message("In over 1 hour", color: PanamStrip.amber)
                message("> 1 h", color: PanamStrip.amber)
            }
        }
    }

    private func message(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
    }
}
