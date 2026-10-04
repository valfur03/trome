import SwiftUI

struct RowTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == RowTitleLabelStyle {
    static var rowTitle: RowTitleLabelStyle { RowTitleLabelStyle() }
}
