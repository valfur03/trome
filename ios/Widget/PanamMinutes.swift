import TROMECore
import SwiftUI

struct PanamMinutes: View {
    private static let textWidth: CGFloat = 400
    /// The timer of iOS shows a second until it is wholly gone (179.5 s left reads "3:00"), so its minutes would read
    /// one more than the rule of `countdownMinutes(at:on:)` in the last second of each minute, and one more than the
    /// spoken wait. Counting to just under a second before the end makes them agree to the millisecond.
    private static let secondShownUntilGone: TimeInterval = 0.999

    let train: LineDirection.Train
    let mode: TransitMode
    let drawnAt: Date

    var body: some View {
        let digits = String(train.countdownMinutes(at: drawnAt, on: mode)).count
        Text(verbatim: String(repeating: "0", count: digits))
            .hidden()
            .overlay {
                if digits > 1 {
                    whileTwoDigits
                }
            }
            .overlay {
                whileOneDigit
            }
            .accessibilityHidden(true)
    }

    private var whileTwoDigits: some View {
        Color.clear
            .overlay(alignment: Alignment(horizontal: .minutesEnd, vertical: .center)) {
                ZStack(alignment: .trailing) {
                    Text("\(timer)\(timer)")
                        .multilineTextAlignment(.trailing)
                        .frame(width: Self.textWidth, alignment: .trailing)
                    Text(verbatim: ":0000:00")
                        .hidden()
                        .alignmentGuide(.minutesEnd) { $0[.leading] }
                }
            }
            .clipped()
    }

    private var whileOneDigit: some View {
        Text(verbatim: "0")
            .hidden()
            .overlay(alignment: Alignment(horizontal: .lastTimerStart, vertical: .center)) {
                ZStack(alignment: .leading) {
                    Text("\(timer)\(Text(verbatim: "0").foregroundStyle(.clear))\(timer)")
                        .multilineTextAlignment(.leading)
                        .frame(width: Self.textWidth, alignment: .leading)
                    Text(verbatim: "00:000")
                        .hidden()
                        .alignmentGuide(.lastTimerStart) { $0[.trailing] }
                }
            }
            .clipped()
    }

    private var timer: Text {
        Text(timerInterval: countdown, countsDown: true, showsHours: false)
    }

    private var countdown: ClosedRange<Date> {
        let end = train.countdownEnd(on: mode).addingTimeInterval(-Self.secondShownUntilGone)
        return min(drawnAt, end)...end
    }
}

private extension HorizontalAlignment {
    enum MinutesEnd: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.trailing]
        }
    }

    enum LastTimerStart: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.trailing]
        }
    }

    static let minutesEnd = HorizontalAlignment(MinutesEnd.self)
    static let lastTimerStart = HorizontalAlignment(LastTimerStart.self)
}
