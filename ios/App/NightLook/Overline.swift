import SwiftUI

struct Overline: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.caption.bold())
            .tracking(0.8)
            .foregroundStyle(NightLook.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}
