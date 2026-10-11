import TROMECore
import SwiftUI

struct IslandNumber: View {
    static let font = Font.system(size: 20, weight: .bold)

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
                WaitDash()
            case .updateTheApp:
                Image.updateTheApp
                    .foregroundStyle(Color.updateTheApp)
            }
        }
        .font(Self.font)
        .monospacedDigit()
    }
}
