import SwiftUI

struct NoTrainsText: View {
    var nextTrainIsOverAnHourAway = false
    var isCompact = false

    var body: some View {
        Text(nextTrainIsOverAnHourAway ? "> 1 h" : "No trains")
            .font(isCompact ? .caption.bold() : .subheadline.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel(nextTrainIsOverAnHourAway ? Text("In over 1 hour") : Text("No trains"))
    }
}
