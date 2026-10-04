import SwiftUI

struct ProblemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: NightLook.buttonHeight)
            .background(NightLook.problem, in: .rect(cornerRadius: NightLook.buttonHeight / 2, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == ProblemButtonStyle {
    static var problem: ProblemButtonStyle { ProblemButtonStyle() }
}
