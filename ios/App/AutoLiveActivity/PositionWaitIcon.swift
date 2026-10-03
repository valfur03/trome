import SwiftUI

struct PositionWaitIcon: View {
    let systemImage: String
    let isWaiting: Bool

    var body: some View {
        Image(systemName: systemImage)
            .opacity(isWaiting ? 0 : 1)
            .overlay {
                if isWaiting {
                    ProgressView()
                        .tint(.accentColor)
                        .accessibilityLabel(Text("Looking for your position"))
                }
            }
    }
}
