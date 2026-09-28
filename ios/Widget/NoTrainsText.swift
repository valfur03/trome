import SwiftUI

struct ServiceEndedText: View {
    var body: some View {
        Text("Service ended")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
