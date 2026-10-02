import RATPCore
import SwiftUI

struct PanamCell: View {
    let train: LineDirection.Train?
    let drawnAt: Date
    let numberFont: Font
    let width: CGFloat

    var body: some View {
        ZStack {
            switch train?.status {
            case .approaching:
                Text(verbatim: "0")
                    .font(numberFont)
            case .atPlatform:
                PanamAtPlatformText()
            case nil:
                if let train {
                    PanamMinutes(train: train, drawnAt: drawnAt)
                        .font(numberFont)
                }
            }
        }
        .monospacedDigit()
        .foregroundStyle(PanamStrip.amber)
        .frame(width: width)
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
