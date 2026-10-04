import SwiftUI

struct ChipLabel<Icon: View>: View {
    let title: Text
    @ViewBuilder let icon: Icon

    var body: some View {
        Label { title } icon: { icon }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NightLook.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: NightLook.minimumTapHeight)
            .background(NightLook.divider, in: .rect(cornerRadius: NightLook.minimumTapHeight / 2, style: .continuous))
            .contentShape(.rect)
    }
}

extension ChipLabel where Icon == Image {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(title: Text(title)) { Image(systemName: systemImage) }
    }
}
