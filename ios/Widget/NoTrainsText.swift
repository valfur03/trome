import SwiftUI

struct NoTrainsText: View {
    var nextTrainIsOverAnHourAway = false
    var isCompact = false

    var body: some View {
        Text(nextTrainIsOverAnHourAway ? "In over 1 hour" : "No trains")
            .font(isCompact ? .caption.bold() : .subheadline.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
