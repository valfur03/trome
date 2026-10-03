#if DEBUG
import SwiftUI

struct ButtonLabel: View {
    let title: Text
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(Text(title), systemImage: systemImage)
    }

    init(_ title: Text, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            oneLine
            ZStack {
                Text(verbatim: " ")
                    .hidden()
                oneLine
                    .font(.callout)
            }
            VStack(spacing: 4) {
                icon
                title
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var oneLine: some View {
        HStack(spacing: 8) {
            icon
            title
                .lineLimit(1)
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .imageScale(.medium)
    }
}
#endif
