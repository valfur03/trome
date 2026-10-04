import SwiftUI

struct IconChip<Icon: View>: View {
    @ViewBuilder let icon: Icon

    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 32

    var body: some View {
        icon
            .font(.body.weight(.semibold))
            .foregroundStyle(NightLook.link)
            .frame(width: size, height: size)
            .background(NightLook.divider, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

extension IconChip where Icon == Image {
    init(systemImage: String) {
        self.init { Image(systemName: systemImage) }
    }
}
