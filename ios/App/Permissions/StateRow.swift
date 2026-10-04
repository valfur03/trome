import SwiftUI

struct StateRow<Title: View>: View {
    let state: LocalizedStringKey
    let kind: StatePill.Kind
    @ViewBuilder let title: Title

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                title
                Spacer(minLength: 0)
                pill
            }
            VStack(alignment: .leading, spacing: 6) {
                title
                pill
            }
        }
    }

    private var pill: some View {
        StatePill(state: state, kind: kind)
    }
}
