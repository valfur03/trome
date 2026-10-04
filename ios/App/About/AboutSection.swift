import SwiftUI

struct AboutSection: View {
    var body: some View {
        NightCard {
            Overline(title: "About")
            LinkRow(
                title: "Privacy policy",
                systemImage: "hand.raised.fill",
                destination: AboutLinks.privacyPolicy
            )
                .accessibilityIdentifier("privacyPolicyLink")
            NightDivider()
            LinkRow(
                title: "Help and feedback",
                systemImage: "bubble.left.fill",
                destination: AboutLinks.helpAndFeedback
            )
                .accessibilityIdentifier("helpLink")
        }
    }
}

private struct LinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Label {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(NightLook.text)
                } icon: {
                    IconChip(systemImage: systemImage)
                }
                .labelStyle(.rowTitle)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.bold())
                    .foregroundStyle(NightLook.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: NightLook.minimumTapHeight)
            .contentShape(.rect)
        }
    }
}
