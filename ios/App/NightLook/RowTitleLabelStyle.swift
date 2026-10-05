import SwiftUI

struct RowTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowTitle(configuration: configuration)
    }
}

extension LabelStyle where Self == RowTitleLabelStyle {
    static var rowTitle: RowTitleLabelStyle { RowTitleLabelStyle() }
}

private struct RowTitle: View {
    let configuration: LabelStyleConfiguration

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                configuration.icon
            }
            configuration.title
                .multilineTextAlignment(.leading)
        }
    }
}
