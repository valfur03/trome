import SwiftUI

struct NoTrainsText: View {
    var nextTrainIsOverAnHourAway = false

    var body: some View {
        Text(nextTrainIsOverAnHourAway ? "In over 1 hour" : "No trains")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
