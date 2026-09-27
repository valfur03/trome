import SwiftUI

struct StateRow<Title: View>: View {
    let state: LocalizedStringKey
    @ViewBuilder let title: Title

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                title
                stateText
            }
        } else {
            HStack {
                title
                Spacer()
                stateText
            }
        }
    }

    private var stateText: some View {
        Text(state)
            .foregroundStyle(.secondary)
    }
}
