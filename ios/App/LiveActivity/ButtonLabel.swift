import SwiftUI

struct ButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                icon
                Text(title)
                    .lineLimit(1)
            }
            VStack(spacing: 4) {
                icon
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .imageScale(.medium)
    }
}

extension View {
    func adaptiveButtonBorderShape() -> some View {
        modifier(AdaptiveButtonBorderShape())
    }
}

private struct AdaptiveButtonBorderShape: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.buttonBorderShape(dynamicTypeSize.isAccessibilitySize ? .roundedRectangle : .automatic)
    }
}
