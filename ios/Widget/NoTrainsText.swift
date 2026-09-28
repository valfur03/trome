import SwiftUI

struct NoTrainsText: View {
    var body: some View {
        Text("No trains")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
