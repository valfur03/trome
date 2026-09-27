import SwiftUI

struct ServingStationName: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "figure.walk")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}
