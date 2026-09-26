import SwiftUI

struct AutomaticModeSection: View {
    var body: some View {
        Section {
            HStack {
                Label("Automatic mode", systemImage: "location.circle")
                Spacer()
                Text("On")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("automaticModeState")
        } footer: {
            Text(
                "The Live Activity starts by itself when you come near a metro or RER station, "
                    + "and stops when you leave."
            )
        }
    }
}
