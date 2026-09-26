import SwiftUI

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
