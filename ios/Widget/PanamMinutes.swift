import RATPCore
import SwiftUI

struct PanamMinutes: View {
    let train: LineDirection.Train
    let drawnAt: Date

    var body: some View {
        Text(verbatim: String(repeating: "0", count: String(train.countdownMinutes(at: drawnAt)).count))
            .hidden()
            .overlay(alignment: Alignment(horizontal: .minutesEnd, vertical: .center)) {
                ZStack(alignment: .trailing) {
                    Text(timerInterval: countdown, countsDown: true, showsHours: false)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 200, alignment: .trailing)
                    Text(verbatim: ":00")
                        .hidden()
                        .alignmentGuide(.minutesEnd) { $0[.leading] }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var countdown: ClosedRange<Date> {
        let end = train.roundedUpCountdownEnd
        return min(drawnAt, end)...end
    }
}

private extension HorizontalAlignment {
    enum MinutesEnd: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.trailing]
        }
    }

    static let minutesEnd = HorizontalAlignment(MinutesEnd.self)
}
