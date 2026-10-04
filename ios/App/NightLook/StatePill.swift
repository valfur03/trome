import SwiftUI

struct StatePill: View {
    enum Kind {
        case fine
        case problem
        case choice(systemImage: String)
    }

    let state: LocalizedStringKey
    let kind: Kind

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(state)
                .textCase(.uppercase)
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var systemImage: String {
        switch kind {
        case .fine: "checkmark"
        case .problem: "exclamationmark.triangle.fill"
        case .choice(let systemImage): systemImage
        }
    }

    private var background: Color {
        switch kind {
        case .fine: NightLook.fine
        case .problem: NightLook.problem
        case .choice: NightLook.divider
        }
    }
}
