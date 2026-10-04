import SwiftUI

struct NightDivider: View {
    var body: some View {
        Rectangle()
            .fill(NightLook.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
