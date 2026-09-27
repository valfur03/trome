import SwiftUI

struct WaitingTime: View {
    static let minimumWidth: CGFloat = 88

    let time: Date

    var body: some View {
        Text(
            .currentDate,
            format: Date.AnchoredRelativeFormatStyle(anchor: time, allowedFields: [.minute], unitsStyle: .abbreviated)
        )
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}
