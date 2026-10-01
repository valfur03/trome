import RATPCore
import SwiftUI

struct IslandNumber: View {
    static let font = Font.title3.bold()

    let value: DynamicIslandWait.MinimalWait
    let drawnAt: Date

    var body: some View {
        Group {
            switch value {
            case .minutes(let train):
                PanamMinutes(train: train, drawnAt: drawnAt)
                    .foregroundStyle(PanamStrip.amber)
            case .zero:
                Text(verbatim: "0")
                    .foregroundStyle(PanamStrip.amber)
            case .dash:
                Text(verbatim: "–")
                    .foregroundStyle(.secondary)
            }
        }
        .font(Self.font)
        .monospacedDigit()
    }
}
